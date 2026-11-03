package sqlite

import (
	"context"
	"errors"
	"path/filepath"
	"testing"

	"rss-server/internal/store"
)

func open(t *testing.T) *DB {
	t.Helper()
	db, err := Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}

func ptr[T any](v T) *T { return &v }

func TestFeedsAndEntries(t *testing.T) {
	ctx := context.Background()
	db := open(t)

	f, err := db.AddFeed(ctx, "https://example.com/feed", "tech")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.AddFeed(ctx, "https://example.com/feed", ""); !errors.Is(err, store.ErrDuplicate) {
		t.Fatalf("want ErrDuplicate, got %v", err)
	}

	es := []store.Entry{
		{GUID: "a", Title: "A", Published: 100},
		{GUID: "b", Title: "B", Published: 200},
		{GUID: "c", Title: "C", Published: 200},
	}
	if err := db.UpsertEntries(ctx, f.ID, es); err != nil {
		t.Fatal(err)
	}
	all, _ := db.ListEntries(ctx, store.EntryFilter{Limit: 10})
	if len(all) != 3 {
		t.Fatalf("want 3 entries, got %d", len(all))
	}

	// Re-upserting must keep read/starred state and update text.
	if err := db.UpdateEntry(ctx, all[0].ID, ptr(true), ptr(true)); err != nil {
		t.Fatal(err)
	}
	es[2].Title = "C2"
	if err := db.UpsertEntries(ctx, f.ID, es); err != nil {
		t.Fatal(err)
	}
	got, _ := db.GetEntry(ctx, all[0].ID)
	if !got.Read || !got.Starred {
		t.Fatalf("upsert reset state: %+v", got)
	}
	if again, _ := db.ListEntries(ctx, store.EntryFilter{Limit: 10}); len(again) != 3 {
		t.Fatalf("upsert duplicated entries: %d", len(again))
	}

	// Cursor pagination over equal published timestamps.
	p1, _ := db.ListEntries(ctx, store.EntryFilter{Limit: 2})
	last := p1[len(p1)-1]
	p2, _ := db.ListEntries(ctx, store.EntryFilter{Limit: 2, Before: &store.Cursor{Published: last.Published, ID: last.ID}})
	if len(p1) != 2 || len(p2) != 1 || p2[0].Title != "A" {
		t.Fatalf("bad pagination: %+v / %+v", p1, p2)
	}

	counts, total, _ := db.UnreadCounts(ctx)
	if total != 2 || len(counts) != 1 || counts[0].Count != 2 {
		t.Fatalf("bad unread counts: %v %d", counts, total)
	}
	if unread, _ := db.ListEntries(ctx, store.EntryFilter{Unread: true, Limit: 10}); len(unread) != 2 {
		t.Fatalf("unread filter: %d", len(unread))
	}
	if starred, _ := db.ListEntries(ctx, store.EntryFilter{Starred: true, Limit: 10}); len(starred) != 1 {
		t.Fatalf("starred filter: %d", len(starred))
	}

	if err := db.MarkAllRead(ctx, &f.ID); err != nil {
		t.Fatal(err)
	}
	if _, total, _ := db.UnreadCounts(ctx); total != 0 {
		t.Fatalf("mark all read left %d", total)
	}

	if err := db.DeleteFeed(ctx, f.ID); err != nil {
		t.Fatal(err)
	}
	if left, _ := db.ListEntries(ctx, store.EntryFilter{Limit: 10}); len(left) != 0 {
		t.Fatalf("cascade delete left %d entries", len(left))
	}
	if err := db.DeleteFeed(ctx, f.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}
}

func TestReopenKeepsSchema(t *testing.T) {
	path := filepath.Join(t.TempDir(), "re.db")
	db, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	db.Close()
	if db, err = Open(path); err != nil {
		t.Fatal(err)
	}
	db.Close()
}
