# Gmail section (AI)

요약: [gmail.md](gmail.md)

Status: implemented. Test: `tests/dashboard_test.lua` with `tests/fake_gws.sh`. Open questions resolved as proposed: opt-in, Mail above feeds, URL template in config.

## Upstream (gws 0.17.0, Homebrew)
- `gws gmail +triage --format json --max <N> [--query <Q>]`. Default query `is:unread`. Read-only.
- Output (verified against a real account): `{ messages = [{ id, from, subject, date }], query, resultSizeEstimate }`. `date` is RFC 2822 (`Tue, 17 Nov 2026 11:37:59 +0000 (GMT)`). An empty inbox is assumed to omit `messages` (handled as `{}`).
- stderr always carries a log line (`Using keyring backend: keyring`); parse stdout only.
- Errors: JSON `{ "error": { code, message, reason } }` on stdout and `error[<reason>]: ...` on stderr, nonzero exit. Not authenticated → `reason = "authError"`.
- Count badge: `resultSizeEstimate` (Gmail's estimate of all matches, not capped by `--max`). No second API call.

## Config (`init.lua` defaults, document in `nvim.ai.md`)
```lua
gmail = {
  enabled = false,                 -- opt-in
  cmd = { "gws" },                 -- argv prefix
  max = 10,
  query = nil,                     -- nil = gws default (is:unread)
  url = "https://mail.google.com/mail/u/0/#all/%s", -- %s = message id; u/N = account
},
```

## gmail.lua (new, `nvim/lua/folo/gmail.lua`)
- Only module that knows gws argv and output. Do not put it in `cli.lua` (folocli envelope `{ok, data}` differs).
- `M.triage(cb(err, items))`: `vim.system(cmd .. { "gmail", "+triage", "--format", "json", "--max", max, ["--query", q] }, { text = true, timeout = cfg.timeout_ms })`, `vim.schedule` the callback (same as `cli.run`).
- Parse: decode stdout; table with `error` → `error.message` (auth → first sentence + hint "run `gws auth login`"); success → `{ total = resultSizeEstimate, messages = { { id, from (display name), subject, date ("17 Nov") } } }`; spawn failure → "cannot run gws: install it or set `gmail.cmd`" (reuse `cli.resolve` for Windows shims).

## ui.lua (dashboard)
- `refresh_dashboard`: start `cli.unread` and, when `cfg.gmail.enabled`, `gmail.triage` in parallel. Keep both results in locals; redraw on each arrival via `draw_dashboard(buf, folo_state, mail_state)`. One failing must not hide the other.
- `draw_dashboard(buf, feeds, mail)`: each `{ data=, err= }`, empty while loading; `mail = nil` when Gmail is off.
- Mail section, above `Unread`:
  ```
    Mail  3

      Alice Kim               Lunch on Friday?  17 Nov
  ```
  - Header: `"  Mail  "` `Title` + `badge(total, ACCENT)` once loaded.
  - Row: from (display name, strip `<addr>`), subject via `one_line`, date short. Fixed columns like feed rows (same `shortcut:` comment pattern).
  - Loading / error / empty: one `Comment` / `ErrorMsg` / `Comment` line ("No unread mail.").
  - `rows[lnum] = { mail = id }`.
- `open_url` (`gx`): `row.mail` → `vim.ui.open(cfg.gmail.url:format(row.mail))`. Errors → `notify_err`. `open` (`<CR>`) shows the body (phase 2).
- `refresh` already calls `refresh_dashboard`; nothing else.
- HELP `dashboard` kind: mention `<CR>` on a mail row opens Gmail in the browser.

## Tests
- `tests/fake_gws.sh`: echo fixture JSON for `gmail +triage`; env var switch for auth error and for empty array.
- `tests/dashboard_test.lua` (extend, set `gmail = { enabled = true, cmd = { fake_gws } }`):
  - Mail header with estimate badge above `Unread`; display name without address; one-line subject + short date.
  - gws auth error → Mail error line, RSS groups still drawn.
  - `enabled = false` → no Mail section; empty inbox → "No unread mail."
  - `<CR>` on mail row → `vim.ui.open` stubbed, receives formatted URL.
- Run: `nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/dashboard_test.lua`.

## Docs
- README: Gmail setup (`brew install gws`, `gws auth setup`, `gws auth login`, `gmail.enabled = true`).
- `nvim.ai.md` options table, `dashboard.md` scope, `progress.md` row.

## Out of scope
Mark read/archive/star (need `gmail.modify` scope), reply/compose, calendar, multiple accounts, auto refresh.

## Phase 2: message body in the preview

Status: implemented against the documented Gmail API shape; not yet run against a real message through gws.

### Upstream
- `gws gmail users messages get --params '{"userId":"me","id":"<id>","format":"full"}'` (verified `--params` flag via `--help`; response shape is Gmail API `Message`, not yet seen through gws).
- `payload`: `{ mimeType, headers = [{name, value}], body = { size, data?, attachmentId? }, filename, parts = [payload...] }`. `body.data` is base64url of the part's bytes in its own charset (from the `Content-Type` header `charset=`); Gmail does not transcode.
- Does not change labels (UNREAD stays).

### gmail.lua
- `M.message(id, cb(err, { subject, from, date, text = lines, attachments = { names } }))`. Reuse `parse`.
- Walk `payload` depth-first: first `text/plain` with `body.data` wins; else first `text/html` → `render.to_lines(html, cfg.render, …)`. Parts with `filename ~= ""` → attachment names, not body.
- Decode: `data:gsub("-", "+"):gsub("_", "/")`, pad `=` to a multiple of 4, `vim.base64.decode`. Charset from the part's `Content-Type` header (`charset="?([%w_-]+)`); when not utf-8/us-ascii, `vim.iconv(s, charset, "utf-8")`, fall back to the raw string when it returns nil/"".
- No body found → `text = { "(no text body)" }`. Normalize CRLF.

### ui.lua
- Dashboard keys: `open` (`<CR>`) on a mail row → show body; new `keymaps.dashboard.open_url = "gx"` → browser (moves the current `<CR>` behaviour). HELP updated.
- Show: `ensure_preview_win(cfg)` from the dashboard window, `setup_preview_keys(cfg)`. Set `preview.list = dashboard_buf` (so `q` returns to the dashboard), `preview.child = false`, `preview.entry = { id = "mail:" .. id, mail = true, title = subject, url = cfg.gmail.url:format(id), feed = from, published = date }` so `draw_preview`/`header` and preview `gx` (`open_urls`) work unchanged.
- Guard on `next_generation()`: draw `status = "Loading…"` first, then the body; a stale reply is dropped.
- Attachments: append `"", "---", "Attachments: a.pdf, b.png"`.
- `render_in_browser`: return early when `preview.entry.mail`.
- Do not use the entry `cache` for mail.
- Moving the cursor on the dashboard does not auto-preview (the dashboard has no CursorMoved hook; keep it).

### Tests (`fake_gws.sh` + `dashboard_test.lua`)
- Fixture `messages get m1`: multipart/alternative with plain + html → plain shown. `m2`: html only, charset euc-kr (bytes via base64url of an EUC-KR string) → readable UTF-8 Korean; one attachment part → name listed.
- `<CR>` on mail row → preview window shows subject header + body; `q` returns to dashboard; `gx` on mail row → `vim.ui.open` with the URL.
