# RSS reader — overview (AI)

요약: [plan.md](plan.md)

## Context
- Folo(RSSNext/folo, AGPL-3.0) analysis: public repo = clients only (Electron `apps/desktop`, Expo `apps/mobile`, `apps/cli`); backend `api.folo.is` is closed.
- Build own self-hosted server + 2 clients. Do NOT copy Folo code. Only the command taxonomy (timeline/entry/subscription/unread/opml, `apps/cli/src/commands/*`) is reference.

## Layout
```
rss/
  docs/     plan, api, config, server, app, nvim (.md + .ai.md each)
  server/   Go module `rss-server` (go.mod already initialized; deps gofeed, modernc sqlite added)
  web/      TypeScript PWA
  nvim/     Lua plugin
  README.md run instructions
```

## Layer docs
- [api.ai.md](api.ai.md): client–server API v1 contract (SSOT)
- [server.ai.md](server.ai.md): packages, store interface, schema, fetcher
- [config.ai.md](config.ai.md): every tunable + deployment profile (SSOT)
- [app.ai.md](app.ai.md): TS PWA, MVVM
- [nvim.ai.md](nvim.ai.md)

## Extensibility decisions (user-confirmed 2026-11-03)
| Topic | Decision | Implication |
|------|------|------|
| Users | Fully single-user | No user_id anywhere. Auth = one bearer token from config |
| Storage | `Store` interface + SQLite impl | Handlers/fetcher depend on interface only; SQL lives in `internal/store/sqlite` |
| HTML sanitize | Server, on save | `bluemonday` UGCPolicy in fetcher before upsert; clients trust `content` |
| Structure | Layered packages + `/api/v1` | `cmd/rss-server`, `internal/{config,store,feed,api,opml}` |
| App (2026-11-04) | TS PWA, Vue 3, MVVM, served by Go | MAUI dropped; see app.ai.md |
| Deploy (2026-11-04) | This Mac now, Tailscale serve for phone, cloud later | No host-specific code; env only (config.ai.md) |

Config defaults in config.ai.md confirmed as-is (2026-11-05).

Rule: any further extensibility-related choice → ask user (see `.claude/skills/plan-docs`).

## Out of scope
AI summary, RSSHub routes, readability extraction, multi-user/OAuth, push, offline cache, realtime sync (lastSyncId).

## Order
server → nvim → web → README (+ one-line link in root README.md)
