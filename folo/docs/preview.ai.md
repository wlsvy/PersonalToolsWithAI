# Folo split view and article preview (AI)

요약: [preview.md](preview.md)

Status: implemented.

## Files
- `lua/folo/article.lua` (new): only module that fetches URLs or knows curl/Chrome. Also URL checks and HTML extraction.
- `lua/folo/ui.lua`: list + preview windows, selection. Replaces the old full-buffer entry view.
- `lua/folo/cli.lua`: `entry()` no longer falls back to readability; the preview chain owns that.
- `lua/folo/init.lua`, `plugin/folo.lua`, `tests/*`, `folo/README.md`, `docs/nvim*.md`.

## Config additions
```lua
list_width = 0.4,           -- fraction of the tab, or columns when >= 1
preview_debounce_ms = 150,
open_confirm_over = 10,     -- confirm when opening more URLs than this
article = {
  auto_fetch = true,        -- false: no automatic curl; Folo readability still runs
  thin_chars = 200,         -- feed body shorter than this (text chars) triggers the chain
  curl_timeout_s = 15,
  max_bytes = 5 * 1024 * 1024,
  browser_cmd = nil,        -- argv prefix; nil = detect Chrome/Chromium
  browser_timeout_ms = 30000,
},
keymaps = {
  list = { open = "<CR>", toggle_select = "<Tab>", toggle_read = "m", open_url = "gx", next_page = "]p", refresh = "r", close = "q" },
  preview = { open_url = "gx", browser = "R", close = "q" },
}
```
`keymaps.timeline`/`keymaps.entry` are removed (single user, no aliases).

## Layout
- Single shared preview buffer `folo://preview`, filetype markdown, `wrap`/`linebreak` on the window.
- Opening a list: if the current window shows the preview, move to the previous window first. Reuse a window in the current tab showing the preview; otherwise `rightbelow vsplit`. Focus stays on the list.
- List `q`: close preview window, delete list buffer. Preview `q`: focus list window (or open it if hidden).

## Preview chain
Key: entry id. Generation counter; every async stage drops its result when stale.
1. Immediately render header from the list item and `Loading…`.
2. `cli.entry(id)` → render feed body. Errors render in the preview; never `vim.notify` from cursor movement.
3. If text of body `< thin_chars`: `cli.readability(id)`; if thin or failed and `auto_fetch`: `article.fetch(url)`.
4. Output: header, feed body, `---`, `## Article (<source>)`, article lines. Feed body is never replaced.
5. Failure: `> Could not load article: <reason>. Press R to render in a browser.`
6. Cache finished results in memory by id. `R` runs `article.render_browser(url)` and overwrites the cache entry.

Debounce on `CursorMoved`; same entry is a no-op. Preview never marks read. `<CR>` marks read and focuses preview.

## article.lua contract
- `safe_url(url)` → `true` or `false, reason`: http/https only; rejects `localhost`, `*.local`, loopback, RFC1918, link-local, CGNAT literals, IPv6 literals. `shortcut:` DNS and redirects are not checked; upgrade to curl `--resolve`-level pinning if these fetches ever carry credentials. No credentials are sent today.
- `fetch(url, cb(err, lines_html))`: `curl -sSL --compressed --proto =http,https --proto-redir =http,https --max-time N --max-filesize M -A <ua> -w <trailer> --url <url>`, `text=false`. Reject HTTP >= 400 and non-HTML content types with a reason.
- `render_browser(url, cb)`: `<browser> --headless=new --disable-gpu --no-first-run --user-data-dir=<tempdir> --virtual-time-budget=5000 --dump-dom <url>`; temp profile deleted afterward. Missing browser → reason.
- `extract(html)`: decode `<meta charset>`/http-equiv or `Content-Type` charset to UTF-8 with `vim.iconv` when not UTF-8; remove script, style, noscript, svg, iframe, nav, header, footer, aside, form blocks (case-insensitive); pick largest `<article>`, else `<main>`, else `<body>`, else whole.
- `text_len(html)`: character count after removing tags.

## Selection and opening
- `<Tab>` toggles selection on the current item and moves down. Selected rows show `+` in the first column; read state stays in the second (`*` = unread).
- Selection is per list, survives paging and read toggles, cleared by refresh and after a successful open.
- `gx` opens all selected, else the current item. http/https only; skipped items are reported. Confirm above `open_confirm_over`. Uses `vim.ui.open`; report per-URL failures.

## Verify
```sh
NVIM_LOG_FILE="$TMPDIR/nvim.log" nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/cli_test.lua
NVIM_LOG_FILE="$TMPDIR/nvim.log" nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/article_test.lua
```
`article_test.lua` puts `fake_curl.sh` on `PATH` as `curl` and sets `fake_browser.sh` as `browser_cmd`. Manual: real account, `:FoloStarred`, move cursor, `<Tab>`, `gx`, `R`.

## Out of scope
Disk cache, images, logged-in pages, bulk mark-read, pluggable extractor interface.
