// Package sqlite implements store.Store on SQLite (modernc.org/sqlite, no cgo).
package sqlite

import (
	"context"
	"database/sql"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"net/url"
	"sort"
	"strings"

	_ "modernc.org/sqlite"

	"rss-server/internal/store"
)

//go:embed migrations/*.sql
var migrations embed.FS

type DB struct{ db *sql.DB }

var _ store.Store = (*DB)(nil)

// Open opens (or creates) the database at path and applies pending migrations.
func Open(path string) (*DB, error) {
	q := url.Values{}
	q.Add("_pragma", "foreign_keys(1)")
	q.Add("_pragma", "journal_mode(WAL)")
	q.Add("_pragma", "busy_timeout(5000)")
	db, err := sql.Open("sqlite", "file:"+path+"?"+q.Encode())
	if err != nil {
		return nil, err
	}
	s := &DB{db: db}
	if err := s.migrate(); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

// migrate runs migrations/NNNN_*.sql whose number is above PRAGMA user_version.
func (s *DB) migrate() error {
	files, err := fs.Glob(migrations, "migrations/*.sql")
	if err != nil {
		return err
	}
	sort.Strings(files)
	var version int
	if err := s.db.QueryRow("PRAGMA user_version").Scan(&version); err != nil {
		return err
	}
	for i, f := range files {
		if i < version {
			continue
		}
		body, err := migrations.ReadFile(f)
		if err != nil {
			return err
		}
		tx, err := s.db.Begin()
		if err != nil {
			return err
		}
		if _, err := tx.Exec(string(body)); err != nil {
			tx.Rollback()
			return fmt.Errorf("migration %s: %w", f, err)
		}
		if _, err := tx.Exec(fmt.Sprintf("PRAGMA user_version = %d", i+1)); err != nil {
			tx.Rollback()
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
	}
	return nil
}

func (s *DB) Close() error { return s.db.Close() }

const feedCols = `f.id, f.url, f.title, f.site_url, f.category, f.etag, f.last_modified, f.last_fetched, f.error,
	(SELECT COUNT(*) FROM entries e WHERE e.feed_id = f.id AND e.read = 0)`

func scanFeed(sc interface{ Scan(...any) error }) (store.Feed, error) {
	var f store.Feed
	err := sc.Scan(&f.ID, &f.URL, &f.Title, &f.SiteURL, &f.Category, &f.ETag, &f.LastModified, &f.LastFetched, &f.Error, &f.Unread)
	return f, err
}

func (s *DB) ListFeeds(ctx context.Context) ([]store.Feed, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+feedCols+` FROM feeds f ORDER BY f.category, f.title, f.id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	feeds := []store.Feed{}
	for rows.Next() {
		f, err := scanFeed(rows)
		if err != nil {
			return nil, err
		}
		feeds = append(feeds, f)
	}
	return feeds, rows.Err()
}

func (s *DB) GetFeed(ctx context.Context, id int64) (store.Feed, error) {
	f, err := scanFeed(s.db.QueryRowContext(ctx, `SELECT `+feedCols+` FROM feeds f WHERE f.id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return f, store.ErrNotFound
	}
	return f, err
}

func (s *DB) AddFeed(ctx context.Context, feedURL, category string) (store.Feed, error) {
	var id int64
	err := s.db.QueryRowContext(ctx,
		`INSERT INTO feeds (url, category) VALUES (?, ?) ON CONFLICT (url) DO NOTHING RETURNING id`,
		feedURL, category).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return store.Feed{}, store.ErrDuplicate
	}
	if err != nil {
		return store.Feed{}, err
	}
	return s.GetFeed(ctx, id)
}

func (s *DB) DeleteFeed(ctx context.Context, id int64) error {
	return expectRow(s.db.ExecContext(ctx, `DELETE FROM feeds WHERE id = ?`, id))
}

func (s *DB) UpdateFeedMeta(ctx context.Context, id int64, m store.FeedMeta) error {
	return expectRow(s.db.ExecContext(ctx,
		`UPDATE feeds SET title = ?, site_url = ?, etag = ?, last_modified = ?, last_fetched = ?, error = ? WHERE id = ?`,
		m.Title, m.SiteURL, m.ETag, m.LastModified, m.LastFetched, m.Error, id))
}

// UpsertEntries inserts new entries and refreshes text fields of known ones,
// leaving read/starred untouched.
func (s *DB) UpsertEntries(ctx context.Context, feedID int64, es []store.Entry) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	stmt, err := tx.PrepareContext(ctx, `INSERT INTO entries (feed_id, guid, url, title, author, content, published)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (feed_id, guid) DO UPDATE SET
			url = excluded.url, title = excluded.title, author = excluded.author, content = excluded.content`)
	if err != nil {
		return err
	}
	defer stmt.Close()
	for _, e := range es {
		if _, err := stmt.ExecContext(ctx, feedID, e.GUID, e.URL, e.Title, e.Author, e.Content, e.Published); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *DB) ListEntries(ctx context.Context, f store.EntryFilter) ([]store.Entry, error) {
	var where []string
	var args []any
	if f.FeedID != nil {
		where = append(where, "feed_id = ?")
		args = append(args, *f.FeedID)
	}
	if f.Unread {
		where = append(where, "read = 0")
	}
	if f.Starred {
		where = append(where, "starred = 1")
	}
	if f.Before != nil {
		where = append(where, "(published < ? OR (published = ? AND id < ?))")
		args = append(args, f.Before.Published, f.Before.Published, f.Before.ID)
	}
	q := `SELECT id, feed_id, url, title, author, published, read, starred FROM entries`
	if len(where) > 0 {
		q += " WHERE " + strings.Join(where, " AND ")
	}
	q += " ORDER BY published DESC, id DESC LIMIT ?"
	args = append(args, f.Limit)

	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	entries := []store.Entry{}
	for rows.Next() {
		var e store.Entry
		if err := rows.Scan(&e.ID, &e.FeedID, &e.URL, &e.Title, &e.Author, &e.Published, &e.Read, &e.Starred); err != nil {
			return nil, err
		}
		entries = append(entries, e)
	}
	return entries, rows.Err()
}

func (s *DB) GetEntry(ctx context.Context, id int64) (store.Entry, error) {
	var e store.Entry
	err := s.db.QueryRowContext(ctx,
		`SELECT id, feed_id, guid, url, title, author, published, read, starred, content FROM entries WHERE id = ?`, id).
		Scan(&e.ID, &e.FeedID, &e.GUID, &e.URL, &e.Title, &e.Author, &e.Published, &e.Read, &e.Starred, &e.Content)
	if errors.Is(err, sql.ErrNoRows) {
		return e, store.ErrNotFound
	}
	return e, err
}

func (s *DB) UpdateEntry(ctx context.Context, id int64, read, starred *bool) error {
	var set []string
	var args []any
	if read != nil {
		set = append(set, "read = ?")
		args = append(args, *read)
	}
	if starred != nil {
		set = append(set, "starred = ?")
		args = append(args, *starred)
	}
	if len(set) == 0 {
		_, err := s.GetEntry(ctx, id)
		return err
	}
	args = append(args, id)
	return expectRow(s.db.ExecContext(ctx, `UPDATE entries SET `+strings.Join(set, ", ")+` WHERE id = ?`, args...))
}

func (s *DB) MarkAllRead(ctx context.Context, feedID *int64) error {
	if feedID == nil {
		_, err := s.db.ExecContext(ctx, `UPDATE entries SET read = 1 WHERE read = 0`)
		return err
	}
	_, err := s.db.ExecContext(ctx, `UPDATE entries SET read = 1 WHERE read = 0 AND feed_id = ?`, *feedID)
	return err
}

func (s *DB) UnreadCounts(ctx context.Context) ([]store.UnreadCount, int, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT feed_id, COUNT(*) FROM entries WHERE read = 0 GROUP BY feed_id ORDER BY feed_id`)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	counts := []store.UnreadCount{}
	total := 0
	for rows.Next() {
		var c store.UnreadCount
		if err := rows.Scan(&c.FeedID, &c.Count); err != nil {
			return nil, 0, err
		}
		counts = append(counts, c)
		total += c.Count
	}
	return counts, total, rows.Err()
}

func expectRow(res sql.Result, err error) error {
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return store.ErrNotFound
	}
	return nil
}
