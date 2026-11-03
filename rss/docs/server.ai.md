# Server (AI)

요약: [server.md](server.md)

## Packages
```
server/
  cmd/rss-server/main.go   wiring only: config → store → fetcher loop → http server, graceful shutdown
  internal/config          env → Config; keys/defaults defined in config.ai.md, nowhere else
  internal/store           Store interface + domain types (Feed, Entry, EntryFilter, UnreadCount)
  internal/store/sqlite    SQLite impl (modernc.org/sqlite), embedded migrations
  internal/feed            Fetcher: conditional GET, gofeed parse, bluemonday sanitize, store upsert
  internal/opml            encoding/xml Parse/Write; no store dependency
  internal/api             net/http handlers (Go 1.22 patterns), auth middleware, JSON helpers
                           + static file server for `RSS_WEB_DIR` at `/` with SPA fallback (no auth on static; auth on /api/v1)
```
- Dependency direction: api, feed → store (interface). Only main imports `store/sqlite`.
- Deps: `github.com/mmcdole/gofeed`, `modernc.org/sqlite`, `github.com/microcosm-cc/bluemonday`. Nothing else.

## Store interface (sketch)
```go
type Store interface {
    ListFeeds(ctx) ([]Feed, error)
    GetFeed(ctx, id int64) (Feed, error)
    AddFeed(ctx, url, category string) (Feed, error)
    DeleteFeed(ctx, id int64) error
    UpdateFeedMeta(ctx, id int64, m FeedMeta) error   // title, site_url, etag, last_modified, last_fetched, error
    UpsertEntries(ctx, feedID int64, es []Entry) error
    ListEntries(ctx, f EntryFilter) ([]Entry, error)  // feed, unread, starred, limit, before cursor
    GetEntry(ctx, id int64) (Entry, error)
    UpdateEntry(ctx, id int64, read, starred *bool) error
    MarkAllRead(ctx, feedID *int64) error
    UnreadCounts(ctx) ([]UnreadCount, int, error)
    Close() error
}
```
- `ErrNotFound` / `ErrDuplicate` sentinels in `store`; api maps to 404 / 409.
- `AddFeed` uses `INSERT ... ON CONFLICT DO NOTHING RETURNING id`; no row → `ErrDuplicate`.

## Schema (SQLite)
- `feeds(id INTEGER PK, url TEXT UNIQUE NOT NULL, title, site_url, category, etag, last_modified, last_fetched INTEGER, error TEXT)`
- `entries(id INTEGER PK, feed_id REFERENCES feeds ON DELETE CASCADE, guid NOT NULL, url, title, author, content, published INTEGER, read INTEGER DEFAULT 0, starred INTEGER DEFAULT 0, UNIQUE(feed_id, guid))`
- Index `entries(published DESC, id DESC)`. `PRAGMA foreign_keys=ON`, WAL.
- Migrations: ordered embedded SQL + `user_version`.

## Fetcher rules
- guid fallback: item.GUID → item.Link → hash(title+published).
- published fallback: Published → Updated → fetch time.
- Upsert keeps `read`/`starred` (ON CONFLICT updates only title/content/url/author).
- `If-None-Match` / `If-Modified-Since`; 304 → only update last_fetched.
- `http.Client{Timeout}`, `io.LimitReader(MaxBodyBytes)`, User-Agent set. Errors stored in `feeds.error`, never crash loop.
- SSRF guard (`internal/feed/client.go`): unless `AllowPrivateFetch`, `net.Dialer.Control` rejects non-public resolved IPs (covers redirects + DNS rebinding); `CheckRedirect` allows only http(s), max 10.
- Entry `url` / feed `siteUrl` kept only if absolute http(s) (`webURL`), so clients never receive `javascript:`/`data:` links.
- Loop: ticker(Interval); feeds fetched with small bounded concurrency; also on-demand `Refresh(id)`.

## API v1 contract
See [api.ai.md](api.ai.md) (single source of truth).

## Tests
- `store/sqlite`: upsert dedupe keeps read state; cursor pagination; unread counts; cascade delete. Use temp file DB.
- `feed`: local `httptest.Server` RSS; 304 path; sanitize strips `<script>`; guid fallback.
- `opml`: round trip, nested categories.
- `api`: 401 without token; add feed → list entries → PATCH read → unread count.

## Verify
`go vet ./... && go test ./...`; `RSS_TOKEN=dev go run ./cmd/rss-server`; curl flow with https://go.dev/blog/feed.atom.
