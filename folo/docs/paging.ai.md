# Auto paging and sort notes (AI)

요약: [paging.md](paging.md)

Status: implemented. Dedup fixture: fake `--cursor 2026-01-01` page repeats id `2` (asserted in `article_test` `]p` and `cli_test` count). Lazy load + help notes: `tests/stars_test.lua`.

## Upstream facts (folocli 0.0.5 dist)
- `timeline` / `collection list`: `--limit` default **20**; `nextCursor = entries.at(-1).entries.publishedAt`, sent back as `publishedAfter`; `hasNext = nextCursor && entries.length >= limit`.
- Implied order: `publishedAt` descending (newest first). Collection uses the entry's `publishedAt`, not star time. Server max limit unknown.

## Config (`init.lua`)
- `lazy_load_margin = 5` -- load the next page when the cursor is within this many rows of the end; 0 = off.

## ui.lua
- In the existing list `CursorMoved` autocmd (not debounced part): if `cfg.lazy_load_margin > 0 and s.next and not s.loading and cursor_row > #s.rows - cfg.lazy_load_margin` → `load_page(s.next)`. `load_page` already guards `s.loading`.
- Trigger only on CursorMoved, never right after `on_page`, so opening a list never chains through the whole history.
- `on_page`: append only entries whose `id` is not in `s.ids` (set keyed by id); `refresh` resets `s.ids`.
- `next_page` (`]p`) unchanged.
- HELP list notes (built at render time so values are live):
  - `("Pages: %s entries per load (page_size), newest first by publish time."):format(cfg.page_size or "20 (CLI default)")`
  - `"Starred list is also ordered by publish time, not star time."`
  - `lazy_load_margin > 0`: `("Next page loads when the cursor is within %d rows of the end."):format(m)`; else `"Auto paging off; use ]p."` (use live `next_page` key).
  - `help_lines` currently reads static `HELP[kind].notes`; allow a note to be a function returning a string (or nil to skip).

## Tests
- `fake_folo.sh` first timeline page returns 2 items, `hasNext=true`; second page (`--cursor 2026-01-01`) returns item id `3`. Add a duplicate of id `2` to that page to test dedup? Changing it affects `cli_test` counts (`#page.entries == 1`) → add a separate cursor case instead, or update the count.
- UI: open `:Folo` with `lazy_load_margin = 5`, move cursor → argv log contains `--cursor`; rows = unique ids. With margin 0 → no `--cursor` call.
- Help popup contains "newest first" and "20 (CLI default)".

## Out of scope
Changing sort, capping list length.
