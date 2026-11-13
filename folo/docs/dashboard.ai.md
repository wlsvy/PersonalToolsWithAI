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
- Shared Folo tab (`enter_tab(panel)`): find the tab with `vim.t.folo_dashboard`, else `tabnew` (its empty buffer is `bufhidden=wipe`). Ensure a header window `topleft 1split` on `folo://header` (`winfixheight`, `winfixbuf` when available), then focus `main_win()` = the first non-float window that is neither header nor preview (`botright new` when none). Sets `vim.t.folo_panel` and redraws the header. `M.timeline` and `M.dashboard` start with it, so every command and nav key lands in that tab's panel window, the preview included.
- Header: one badge per `keymaps.nav` entry (`dashboard D`, `timeline T`, `unread U`, `starred *`); active panel uses `FoloBadgeOn<hex>` (filled). Panel of a list = first part of its title (`all` → timeline). `map_nav` maps them on the header, dashboard, every list and the preview.
- List `close`: `M.dashboard()` then `bdelete` the list. Dashboard `close`: `tabclose`; on the last tab clear `folo_dashboard`, `only`, `bdelete`.
- `M.dashboard()`:
  - `enter_tab("dashboard")`, close the preview, show `dashboard_buf` in the panel window.
  - Buffer `create_scratch("Folo Dashboard", "folo-dashboard")`, remembered in `dashboard_buf`: a name without a scheme is stored as a full path, so `find_buf` cannot find it; `nowrap`, `nonumber`, `cursorline`.
  - Fetch `cli.unread`, then draw. Show `Loading…` line while waiting; errors → `notify_err`.
- Layout:
  ```
    Dashboard (D)   Timeline (T)   Unread (U)   Starred (*)     <- header window

    Unread  2690

    Recommended  1953
      1x.com • In Pursuit of the Sublime        1313
      ...
  ```
  - Groups sorted by sum desc, feeds by `unreadCount` desc; empty category → `Uncategorized` (header not openable: no CLI filter for it).
  - `rows[lnum] = { category = name }` or `{ feed = feedId, title = }` for `<CR>`.
- Badge (rim): `"\u{e0b6}" .. text .. "\u{e0b4}"` (nf-ple-left/right_half_circle_thick). Caps: `fg = rim`. Body: `bg = darken(rim, 0.3), fg = rim, bold`; active: `bg = rim, fg = darken(rim, 0.2)`. Highlight via extmarks in a dashboard namespace; groups `FoloRim<hex>`, `FoloBadge<hex>` created with `nvim_set_hl` on each draw (same as icon groups). Rim colors: header badges from `icons.palette` by index, counts one fixed accent. `darken` = per-channel multiply, ~5 lines, no dependency.
- `open`: category row → `M.timeline({ unread = true, category = name }, name)`; feed row → `M.timeline({ unread = true, feed = id }, title)`. Opens in the panel window via `enter_tab`.
- HELP: add a `dashboard` kind to `help_lines`.
- Dashboard keys (`keymaps.dashboard`): `open`, `refresh`, `close`, `help`. Navigation moved to `keymaps.nav`; the dashboard has no button row of its own.

## plugin/folo.lua
- `:Folo` → `require("folo.ui").dashboard()`.
- `:FoloCategory`, `ui.category`, `ui.pick_category`, `cli.categories` removed: the dashboard's category rows replace them (unread only). `cli.timeline` keeps `--category`. Tests open category lists with `ui.timeline({ category = X }, "category/" .. X)`.

## Tests (`tests/fake_folo.sh`, new `tests/dashboard_test.lua`)
- Fake `unread list` with two views and an item without category.
- Assert: view filter and total; group order; `Uncategorized`; rim caps present in line 1; `<CR>` on feed row → `timeline --feed <id> --unread-only` argv; second `:Folo` reuses the tab (tab count unchanged).

## Docs
- README command table: `:Folo` → dashboard. `nvim.ai.md` options: `keymaps.dashboard`. `progress.md` row after implementation.

## Out of scope
Site icons on feed rows, fold/unfold, auto refresh, mark-read from dashboard.
