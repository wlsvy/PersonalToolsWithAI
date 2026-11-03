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
  src/router.ts            vue-router (hash or history; history needs server SPA fallback)
  public/manifest.webmanifest, service worker (app shell cache only; no offline data — out of scope)
```
- Entry view: render server-sanitized `content` in a sandboxed container; page CSP `script-src 'self'`.
- Tooling: Vite + TypeScript + Vue + vue-router + Vitest (node 24 present). PWA manifest/SW: `vite-plugin-pwa` (ask before adding if a hand-written SW suffices).

## Verify
`vitest` for viewmodels and api client (mock fetch); manual: Mac browser at localhost, phone via Tailscale HTTPS URL; check install prompt.
