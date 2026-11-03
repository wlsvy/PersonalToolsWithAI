package feed

import (
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"

	"rss-server/internal/config"
	"rss-server/internal/store"
	"rss-server/internal/store/sqlite"
)

const rss = `<?xml version="1.0"?>
<rss version="2.0"><channel><title>Test Feed</title><link>https://example.com</link>
<item><guid>g1</guid><title>One</title><link>https://example.com/1</link>
<description><![CDATA[<p>hi</p><script>alert(1)</script>]]></description>
<pubDate>Mon, 02 Nov 2026 10:00:00 GMT</pubDate></item>
<item><title>No guid</title><link>https://example.com/2</link></item>
<item><title>No guid or link</title></item>
</channel></rss>`

func setup(t *testing.T) (*Fetcher, store.Store, *httptest.Server, *atomic.Int32) {
	t.Helper()
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		if r.Header.Get("If-None-Match") == `"v1"` {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		w.Header().Set("ETag", `"v1"`)
		w.Write([]byte(rss))
	}))
	t.Cleanup(srv.Close)
	db, err := sqlite.Open(filepath.Join(t.TempDir(), "f.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	cfg, _ := config.Load(func(k string) string { return map[string]string{"RSS_TOKEN": "t"}[k] })
	return New(db, cfg), db, srv, &hits
}

func TestRefresh(t *testing.T) {
	ctx := context.Background()
	f, db, srv, hits := setup(t)
	fd, _ := db.AddFeed(ctx, srv.URL, "")

	got, err := f.Refresh(ctx, fd.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Title != "Test Feed" || got.Error != "" || got.Unread != 3 {
		t.Fatalf("unexpected feed: %+v", got)
	}

	es, _ := db.ListEntries(ctx, store.EntryFilter{Limit: 10})
	for _, e := range es {
		full, _ := db.GetEntry(ctx, e.ID)
		if strings.Contains(full.Content, "<script") {
			t.Fatalf("script not sanitized: %q", full.Content)
		}
		switch full.Title {
		case "No guid":
			if full.GUID != "https://example.com/2" {
				t.Fatalf("guid fallback to link failed: %q", full.GUID)
			}
		case "No guid or link":
			if !strings.HasPrefix(full.GUID, "sha256:") {
				t.Fatalf("guid fallback to hash failed: %q", full.GUID)
			}
		}
	}

	// Second refresh sends the ETag, gets 304, and keeps entries.
	got, err = f.Refresh(ctx, fd.ID)
	if err != nil || got.Error != "" || got.Unread != 3 || hits.Load() != 2 {
		t.Fatalf("304 path: feed=%+v err=%v hits=%d", got, err, hits.Load())
	}
}

func TestRefreshRecordsFetchError(t *testing.T) {
	ctx := context.Background()
	f, db, _, _ := setup(t)
	fd, _ := db.AddFeed(ctx, "http://127.0.0.1:1/nope", "")
	got, err := f.Refresh(ctx, fd.ID)
	if err != nil {
		t.Fatalf("fetch error must not be returned: %v", err)
	}
	if got.Error == "" {
		t.Fatal("fetch error not recorded")
	}
}
