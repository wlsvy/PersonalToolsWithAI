package api

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"rss-server/internal/config"
	"rss-server/internal/feed"
	"rss-server/internal/store/sqlite"
)

const testRSS = `<?xml version="1.0"?><rss version="2.0"><channel><title>T</title>
<item><guid>1</guid><title>One</title><pubDate>Mon, 02 Nov 2026 10:00:00 GMT</pubDate></item>
<item><guid>2</guid><title>Two</title><pubDate>Tue, 03 Nov 2026 10:00:00 GMT</pubDate></item>
</channel></rss>`

type client struct {
	t     *testing.T
	base  string
	token string
}

func (c client) do(method, path, body string, out any) int {
	c.t.Helper()
	req, _ := http.NewRequest(method, c.base+path, strings.NewReader(body))
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer resp.Body.Close()
	if out != nil {
		if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
			c.t.Fatalf("%s %s: decode: %v", method, path, err)
		}
	}
	return resp.StatusCode
}

func setup(t *testing.T, env map[string]string) (string, string) {
	t.Helper()
	feedSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, testRSS)
	}))
	t.Cleanup(feedSrv.Close)

	env["RSS_TOKEN"] = "secret"
	env["RSS_ALLOW_PRIVATE_FETCH"] = "1" // test feeds run on loopback
	cfg, err := config.Load(func(k string) string { return env[k] })
	if err != nil {
		t.Fatal(err)
	}
	db, err := sqlite.Open(filepath.Join(t.TempDir(), "api.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	srv := httptest.NewServer(New(db, feed.New(db, cfg), cfg))
	t.Cleanup(srv.Close)
	return srv.URL, feedSrv.URL
}

func TestAPIFlow(t *testing.T) {
	base, feedURL := setup(t, map[string]string{})
	anon := client{t, base + basePath, ""}
	c := client{t, base + basePath, "secret"}

	if code := anon.do("GET", "/feeds", "", nil); code != 401 {
		t.Fatalf("no token: want 401, got %d", code)
	}
	if code := (client{t, base + basePath, "wrong"}).do("GET", "/feeds", "", nil); code != 401 {
		t.Fatalf("bad token: want 401, got %d", code)
	}

	var fd struct {
		ID     int64
		Title  string
		Unread int
	}
	if code := c.do("POST", "/feeds", `{"url":"`+feedURL+`"}`, &fd); code != 201 || fd.Unread != 2 {
		t.Fatalf("add feed: code=%d feed=%+v", code, fd)
	}
	if code := c.do("POST", "/feeds", `{"url":"`+feedURL+`"}`, nil); code != 409 {
		t.Fatalf("duplicate feed: want 409, got %d", code)
	}
	if code := c.do("POST", "/feeds", `{"url":"file:///etc/passwd"}`, nil); code != 400 {
		t.Fatalf("bad scheme: want 400, got %d", code)
	}

	type page struct {
		Entries []struct {
			ID    int64
			Title string
			Read  bool
		}
		Next *string
	}
	var p1 page
	c.do("GET", "/entries?limit=1", "", &p1)
	if len(p1.Entries) != 1 || p1.Entries[0].Title != "Two" || p1.Next == nil {
		t.Fatalf("page 1: %+v", p1)
	}
	var p2 page
	c.do("GET", "/entries?limit=1&before="+*p1.Next, "", &p2)
	if len(p2.Entries) != 1 || p2.Entries[0].Title != "One" || p2.Next != nil {
		t.Fatalf("page 2: %+v", p2)
	}

	id := p1.Entries[0].ID
	if code := c.do("PATCH", "/entries/"+itoa(id), `{"read":true}`, nil); code != 204 {
		t.Fatalf("patch: %d", code)
	}
	if code := c.do("PATCH", "/entries/999999", `{"read":true}`, nil); code != 404 {
		t.Fatalf("patch missing: want 404, got %d", code)
	}
	var unread struct{ Total int }
	c.do("GET", "/unread", "", &unread)
	if unread.Total != 1 {
		t.Fatalf("unread after patch: %d", unread.Total)
	}

	if code := c.do("POST", "/entries/read-all", "", nil); code != 204 {
		t.Fatalf("read-all: %d", code)
	}
	c.do("GET", "/unread", "", &unread)
	if unread.Total != 0 {
		t.Fatalf("unread after read-all: %d", unread.Total)
	}

	// OPML: export, delete, re-import.
	req, _ := http.NewRequest("GET", c.base+"/opml", nil)
	req.Header.Set("Authorization", "Bearer secret")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	doc, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(doc), feedURL) {
		t.Fatalf("opml export missing feed: %s", doc)
	}
	c.do("DELETE", "/feeds/"+itoa(fd.ID), "", nil)
	var imp struct{ Added, Skipped int }
	if code := c.do("POST", "/opml", string(doc), &imp); code != 200 || imp.Added != 1 {
		t.Fatalf("opml import: code=%d %+v", code, imp)
	}
}

func TestSPAFallback(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "index.html"), []byte("INDEX"), 0o644)
	os.WriteFile(filepath.Join(dir, "app.js"), []byte("JS"), 0o644)
	base, _ := setup(t, map[string]string{"RSS_WEB_DIR": dir})

	for path, want := range map[string]string{"/": "INDEX", "/feeds/3": "INDEX", "/app.js": "JS", "/../secret": "INDEX"} {
		resp, err := http.Get(base + path)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if string(body) != want {
			t.Errorf("%s: got %q want %q", path, body, want)
		}
	}
}

func itoa(n int64) string {
	b, _ := json.Marshal(n)
	return string(b)
}
