# Auto paging and sort notes (AI)

요약: [paging.md](paging.md)

Status: implemented. Dedup fixture: fake `--cursor 2026-01-01` page repeats id `2` (asserted in `article_test` `]p` and `cli_test` count). Lazy load + help notes: `tests/stars_test.lua`.

## Upstream facts (folocli 0.0.5 dist)
- `timeline` / `collection list`: `--limit` default **20**; `nextCursor = entries.at(-1).entries.publishedAt`, sent back as `publishedAfter`; `hasNext = nextCursor && entries.length >= limit`.
- `timeline` order: `publishedAt` descending (newest first). Server max limit unknown.
- `collection list` order (observed live 2026-11-08): `collections.createdAt` descending, so the server reads `publishedAfter` as a star time. The CLI's `nextCursor` is still a `publishedAt`.
  - Effect on a 39-entry collection: CLI cursor returns 21 unique (p2 n=1, `hasNext=false`, 18 skipped); `createdAt` cursor returns 39 (p2 n=19, no repeats).

## Collection cursor fix (`cli.lua`)
- `normalize`: add `starred_at = item.collections and item.collections.createdAt`.
- `M.collection`: when `page.next` is set, replace it with `page.entries[#page.entries].starred_at or page.next`. Non-empty is guaranteed: `next` only exists when the CLI saw a last entry.
- Keep the CLI's `hasNext` (full page) as the stop rule. `timeline` is unchanged.
- `ui.lua` paging logic is unchanged; only the note and comment below change.

## Config (`init.lua`)
- `lazy_load_margin = 5` -- load the next page when the cursor is within this many rows of the end; 0 = off.

## ui.lua
- In the existing list `CursorMoved` autocmd (not debounced part): if `cfg.lazy_load_margin > 0 and s.next and not s.loading and cursor_row > #s.rows - cfg.lazy_load_margin` → `load_page(s.next)`. `load_page` already guards `s.loading`.
- Trigger only on CursorMoved, never right after `on_page`, so opening a list never chains through the whole history.
- `on_page`: append only entries whose `id` is not in `s.ids` (set keyed by id); `refresh` resets `s.ids`.
- `next_page` (`]p`) unchanged.
- HELP list notes (built at render time so values are live):
  - `("Pages: %s entries per load (page_size), newest first by publish time."):format(cfg.page_size or "20 (CLI default)")`
  - `"The starred list is newest first by star time; rows show the publish date."`
- `on_page` comment (`ui.lua`): "The cursor is a publish time" → a timestamp, since collection cursors are star times.
  - `lazy_load_margin > 0`: `("Next page loads when the cursor is within %d rows of the end."):format(m)`; else `"Auto paging off; use ]p."` (use live `next_page` key).
  - `help_lines` currently reads static `HELP[kind].notes`; allow a note to be a function returning a string (or nil to skip).

## Tests
- `fake_folo.sh` first timeline page returns 2 items, `hasNext=true`; second page (`--cursor 2026-01-01`) returns item id `3`. Add a duplicate of id `2` to that page to test dedup? Changing it affects `cli_test` counts (`#page.entries == 1`) → add a separate cursor case instead, or update the count.
- UI: open `:Folo` with `lazy_load_margin = 5`, move cursor → argv log contains `--cursor`; rows = unique ids. With margin 0 → no `--cursor` call.
- Help popup contains "newest first" and "20 (CLI default)". `stars_test.lua` help assertion: "not by star time" → "by star time".
- Collection cursor:
  - `fake_folo.sh`: first `collection list` page gets `collections.createdAt` different from `publishedAt`, and `hasNext=true`; add a `--cursor <createdAt>` case returning a second page. Match it before the generic `collection list` case. A publish-time cursor must not match it.
  - `stars_test.lua`: assert `page.next` is the `createdAt`, the argv carries it, and the second page's entries are starred.
  - Check existing assertions that read the single-page collection fixture.
- Also update `stars.ai.md`: `collections.createdAt` is now confirmed in real output.
- Run: `nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/<name>_test.lua` for `cli`, `article`, `ai`, `stars`, `icons`.

## Out of scope
Changing sort, capping list length, showing the star date in rows, patching folocli.
