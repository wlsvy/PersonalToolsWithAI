# Client–server API v1 (AI)

요약: [api.md](api.md)

Single source of truth for the contract. Server (`internal/api`) and every client (nvim `lua/rss/api.lua`, app API service) must match this file; change here first.

## Conventions
- Base path `/api/v1`. Breaking changes → `/api/v2`, keep v1 until clients migrate.
- Auth: `Authorization: Bearer <token>`; missing/wrong → `401 {"error":"unauthorized"}`.
- JSON (`application/json; charset=utf-8`), camelCase fields. Timestamps = Unix seconds (int64).
- Errors: `{"error":"<message>"}` with 400 (bad input), 401, 404 (`store.ErrNotFound`), 409 (duplicate feed url), 500.
- Numeric limits (default/max page size, OPML body size) come from server config, not hardcoded. Values below are config defaults pending user confirmation.

## Types
```ts
Feed  = { id, url, title, siteUrl, category, lastFetched, error, unread }
Entry = { id, feedId, url, title, author, published, read, starred, content? }  // content only in GET /entries/{id}
Page  = { entries: Entry[], next: string | null }   // next = opaque cursor "<published>:<id>"
```

## Endpoints
| Method | Path | Request | Response |
|---|---|---|---|
| GET | /feeds | – | `200 Feed[]` |
| POST | /feeds | `{url, category?}` | `201 Feed` (fetched once synchronously; fetch error kept in `error`, still 201) / 409 |
| DELETE | /feeds/{id} | – | `204` (entries cascade) |
| POST | /feeds/{id}/refresh | – | `200 Feed` |
| GET | /entries | query `feed?`, `unread=1?`, `starred=1?`, `limit?` (default 50, max 200), `before?` (cursor) | `200 Page` sorted published DESC, id DESC |
| GET | /entries/{id} | – | `200 Entry` with sanitized `content` |
| PATCH | /entries/{id} | `{read?: bool, starred?: bool}` | `204` |
| POST | /entries/read-all | query `feed?` (omit = all) | `204` |
| GET | /unread | – | `200 {feeds: [{feedId, count}], total}` |
| GET | /opml | – | `200 text/x-opml` |
| POST | /opml | OPML XML body | `200 {added, skipped}` (existing urls skipped) |

## Client notes
- `content` is server-sanitized (bluemonday UGC); clients may render directly, app WebView still sets CSP.
- Pagination: pass `next` back as `before` until `next == null`.
