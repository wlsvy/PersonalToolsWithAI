# App — TS PWA (AI)

요약: [app.md](app.md)

## Decisions
- TypeScript PWA, single codebase (user-confirmed 2026-11-04). Replaces .NET MAUI; no Xcode/Android SDK needed.
- MVVM (user-confirmed): View (components) ↔ ViewModel (state + commands) ↔ Model (API client). Views hold no fetch/business logic.
- UI: Vue 3 (Composition API). ViewModel = composable (`useFeedsVM()` etc.) returning reactive state + commands; views are SFCs binding only to VM.
- Served by Go server from built `web/dist` (same origin, no CORS). Path in `RSS_WEB_DIR` (config.ai.md).
- Phone access: Tailscale `serve` → HTTPS → `http://127.0.0.1:<port>`; secure context satisfies SW/install.
- Auth stays bearer token (shared with nvim); cookie auth not needed now.
- Later native store app: wrap with Capacitor (not now).

## Structure
```
web/
  src/api/client.ts        API v1 client; types mirror api.ai.md; only module that knows paths
  src/config/settings.ts   serverUrl/token (see config.ai.md)
  src/viewmodels/          useFeedsVM, useEntriesVM, useEntryVM, useSettingsVM — testable without DOM
  src/views/               Settings.vue, Feeds.vue, Entries.vue, Entry.vue
  src/viewmodels/async.ts  shared loading/error wrapper
  src/inject.ts            provide/inject key for the Client
  src/router.ts            vue-router history mode (server SPA fallback); guard → /settings when no token
  public/manifest.webmanifest, public/icon.svg (no service worker: offline is out of scope; install works without it)
```
- Entry view: `v-html` of server-sanitized `content`; page CSP meta in `index.html` (`script-src 'self'`, `object-src 'none'`).
- Entries paging: "더 보기" button using cursor `next` (no infinite scroll).
- Tooling: Vite + TypeScript + Vue + vue-router + Vitest. No `vite-plugin-pwa`.
- Icon is SVG only; iOS home screen ignores SVG apple-touch-icon (falls back to screenshot). Add PNG icons if that matters.

## Verify
`vitest` for viewmodels and api client (mock fetch); manual: Mac browser at localhost, phone via Tailscale HTTPS URL; check install prompt.
