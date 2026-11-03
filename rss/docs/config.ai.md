# Config (AI)

요약: [config.md](config.md)

Single source of truth for every tunable. Code reads config only through `internal/config` (server), the settings model (web app), `setup()` opts (nvim). No literal defaults elsewhere. Defaults below are proposals pending user confirmation.

## Server (env, parsed in `internal/config`)
| Env | Type | Default | Notes |
|---|---|---|---|
| `RSS_ADDR` | host:port | `127.0.0.1:8080` | bind local only; phone reaches it through Tailscale serve |
| `RSS_DB` | path | `./rss.db` | SQLite file |
| `RSS_TOKEN` | string | – (required) | refuse to start if empty |
| `RSS_INTERVAL` | duration | `30m` | fetch loop period |
| `RSS_FETCH_TIMEOUT` | duration | `20s` | per feed request |
| `RSS_FETCH_CONCURRENCY` | int | `4` | parallel feed fetches |
| `RSS_MAX_FEED_BYTES` | int | `10485760` (10MB) | `io.LimitReader` on feed body |
| `RSS_MAX_OPML_BYTES` | int | `2097152` (2MB) | POST /opml body limit |
| `RSS_PAGE_DEFAULT` | int | `50` | GET /entries default limit |
| `RSS_PAGE_MAX` | int | `200` | GET /entries max limit |
| `RSS_USER_AGENT` | string | `rss-server/<version>` | fetch UA |
| `RSS_WEB_DIR` | path | empty | built web app (`web/dist`); empty = API only, no static serving |
- Validation at startup: bad duration/int → exit with message. Durations via `time.ParseDuration`.
- Optional `.env` loading: no (keep env only; launchd/shell provides it).

## Web app (PWA, settings model)
| Key | Storage | Notes |
|---|---|---|
| `serverUrl` | localStorage | empty = same origin (default, since Go serves the app) |
| `token` | localStorage | XSS mitigated by server sanitize + CSP |

## nvim (`require("rss").setup{}`)
| Opt | Default | Fallback |
|---|---|---|
| `url` | – | env `RSS_URL` |
| `token` | – | env `RSS_TOKEN` |
| `api_base` | `/api/v1` | |
| `page_size` | nil (server default) | |
| `keymaps` | see [nvim.ai.md](nvim.ai.md) | |
| `render` | `"auto"` (pandoc if found) | `"pandoc"` / `"strip"` |

## Deployment profile: this Mac (current)
- Run `rss-server` with env from a launchd plist (`~/Library/LaunchAgents/`) or shell; DB under `~/Library/Application Support/rss/` suggested via `RSS_DB`.
- Phone: Tailscale on Mac + phone; `tailscale serve --bg 8080` → `https://<mac>.<tailnet>.ts.net`. Not in code; ops only.
- Cloud later = same binary, different env. Nothing Mac-specific in code.
