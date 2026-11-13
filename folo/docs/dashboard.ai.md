# Dashboard (AI)

요약: [dashboard.md](dashboard.md)

Status: implemented. Test: `tests/dashboard_test.lua`. Other tests open the timeline with `ui.timeline({}, "all")` since `:Folo` is the dashboard.

## Upstream (folocli 0.0.5, verified against a real account)
- `unread list` → `data.total`, `data.items[]`: `{ sourceType, sourceId, feedId, title, category, view (number), unreadCount, isPrivate }`.
- `timeline --feed <feedId>` filters by feed; combines with `--unread-only`.

## cli.lua
- `unread(cb(err, {total=, items=}))`: run `{ "unread", "list" }`. Filter items by `cfg.view` when set; `cfg.view` may be a name ("articles") or number, map names to numbers (articles 0, social 1, pictures 2, videos 3, audio 4, notifications 5). `total` = sum of kept `unreadCount` (not `data.total`, which spans all views).
- `timeline`: `add_flag(args, "--feed", opts.feed)`.

## ui.lua
- `M.dashboard()`:
  - Find a tab whose `vim.t[tab].folo_dashboard` is true → `nvim_set_current_tabpage`, close its preview, show the dashboard; else `tab sbuffer`, set `vim.t.folo_dashboard = true`, `vim.t.tabname = "Folo Dashboard"`.
  - Buffer `create_scratch("Folo Dashboard", "folo-dashboard")`, remembered in `dashboard_buf`: a name without a scheme is stored as a full path, so `find_buf` cannot find it; `nowrap`, `nonumber`, `cursorline`.
  - Fetch `cli.unread`, then draw. Show `Loading…` line while waiting; errors → `notify_err`.
- Layout:
  ```
    Folo   Timeline (t)  Unread (u)  Starred (s)  Category (c)  Refresh (r)  Help (?)

    Unread  2690

    Recommended  1953
      1x.com • In Pursuit of the Sublime        1313
      ...
  ```
  - Groups sorted by sum desc, feeds by `unreadCount` desc; empty category → `Uncategorized` (header not openable: no CLI filter for it).
  - `rows[lnum] = { category = name }` or `{ feed = feedId, title = }` for `<CR>`.
- Badge (rim): `"\u{e0b6}" .. text .. "\u{e0b4}"` (nf-ple-left/right_half_circle_thick). Caps: `fg = rim`. Body: `bg = darken(rim, 0.3), fg = rim, bold`. Highlight via extmarks in a dashboard namespace; groups `FoloRim<hex>`, `FoloBadge<hex>` created with `nvim_set_hl` on each draw (same as icon groups). Rim colors: buttons from `icons.palette` by index, counts one fixed accent. `darken` = per-channel multiply, ~5 lines, no dependency.
- Keys (`keymaps.dashboard` in init.lua defaults): `timeline = "t"`, `unread = "u"`, `starred = "s"`, `category = "c"`, `refresh = "r"`, `open = "<CR>"`, `close = "q"` (close tab; last tab → `bdelete`), `help = "?"`. Buttons reuse `M.timeline`, `M.starred`, `M.pick_category`.
- `open`: category row → `M.timeline({ unread = true, category = name }, name)`; feed row → `M.timeline({ unread = true, feed = id }, title)`. Opens in the dashboard tab's window; list `close` sets `dashboard_buf` in the window before `bdelete` when `vim.t.folo_dashboard`.
- HELP: add a `dashboard` kind to `help_lines`.

## plugin/folo.lua
- `:Folo` → `require("folo.ui").dashboard()`. Others unchanged.

## Tests (`tests/fake_folo.sh`, new `tests/dashboard_test.lua`)
- Fake `unread list` with two views and an item without category.
- Assert: view filter and total; group order; `Uncategorized`; rim caps present in line 1; `<CR>` on feed row → `timeline --feed <id> --unread-only` argv; second `:Folo` reuses the tab (tab count unchanged).

## Docs
- README command table: `:Folo` → dashboard. `nvim.ai.md` options: `keymaps.dashboard`. `progress.md` row after implementation.

## Out of scope
Site icons on feed rows, fold/unfold, auto refresh, mark-read from dashboard.
