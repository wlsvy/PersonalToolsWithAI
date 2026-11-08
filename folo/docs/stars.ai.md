# Stars / collection (AI)

요약: [stars.md](stars.md)

Status: implemented. Test: `tests/stars_test.lua`; `article_test`/`ai_test` set `lazy_load_margin = 0`.

## Upstream (folocli 0.0.5 dist, client-sdk types)
- `collection add <entryId> [--view]` → `client.api.collections.post({entryId, view})`.
- `collection remove <entryId>` → `client.api.collections.delete({entryId})`.
- List items may carry `collections?: { createdAt }` (`EntryExtraResponse`). Confirmed in real `collection list` output; it is the paging key there ([paging.ai.md](paging.ai.md)).

## cli.lua
- `normalize`: `starred = item.collections ~= nil`.
- `collection(opts, cb)`: force `starred = true` on every entry (list is the collection itself).
- `set_starred(id, starred, cb(err))`: `{ "collection", starred and "add" or "remove", id }`. No `--view` (optional upstream).

## ui.lua
- Keymap `keymaps.list.toggle_star = "S"` in `init.lua` defaults; HELP list row `{ "toggle_star", "Star or unstar selected entries, or the current one" }`.
- Targets: `targets()` (selection, else current). New state: `want = not all(starred)`. Run `cli.set_starred` per entry; on each success set `e.starred = want` and `redraw`; errors → `notify_err`, entry unchanged. Clear selection after dispatch (same as `queue`).
- Starred view: unstar keeps the row; only the mark changes.
- Row format: `selected .. mark .. " " .. star .. " " .. icon .. date ...`, `star = e.starred and "⭐" or "  "` (two spaces keep columns aligned). Always shown (no config toggle).
- HELP list note: "Row marks: + selected, * unread, ⭐ starred."

## Tests (`tests/fake_folo.sh`, new `tests/stars_test.lua` or extend `cli_test.lua`)
- Fake: `collection add|remove` → ok; one timeline item with `"collections":{"createdAt":"..."}`.
- Assert argv, `starred` normalize, collection forces true.
- UI: `S` on unstarred → `collection add <id>` and ⭐ in line; again → `remove`, ⭐ gone, row stays; failure mode leaves state.
- Update existing list-line assertion in `article_test.lua` (two spaces for unstarred).

## Out of scope
Preview key, sort by star time, `--view` on add.
