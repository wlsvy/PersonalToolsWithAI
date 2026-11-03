package opml

import (
	"bytes"
	"reflect"
	"strings"
	"testing"
)

func TestRoundTrip(t *testing.T) {
	in := []Item{
		{URL: "https://a.com/feed", Title: "A", SiteURL: "https://a.com", Category: "tech"},
		{URL: "https://b.com/feed", Title: "B"},
		{URL: "https://c.com/feed", Title: "C", Category: "tech"},
	}
	var buf bytes.Buffer
	if err := Write(&buf, "rss", in); err != nil {
		t.Fatal(err)
	}
	out, err := Parse(&buf)
	if err != nil {
		t.Fatal(err)
	}
	// Write groups by category, so the order becomes: tech folder (A, C), then B.
	want := []Item{in[0], in[2], in[1]}
	if !reflect.DeepEqual(out, want) {
		t.Fatalf("got %+v\nwant %+v", out, want)
	}
}

func TestNestedCategoryUsesNearestFolder(t *testing.T) {
	src := `<opml version="2.0"><body>
<outline text="Outer"><outline text="Inner">
  <outline text="X" xmlUrl="https://x.com/feed"/>
</outline></outline></body></opml>`
	items, err := Parse(strings.NewReader(src))
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].Category != "Inner" || items[0].Title != "X" {
		t.Fatalf("unexpected: %+v", items)
	}
}
