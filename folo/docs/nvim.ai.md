# Folo nvim plugin (AI)

요약: [nvim.md](nvim.md)

Status: implemented.

## Files
```
folo/
  README.md
  docs/nvim.md, nvim.ai.md
  nvim/
    plugin/folo.lua      user commands only, lazy-require
    lua/folo/init.lua    setup(opts), config merge
    lua/folo/cli.lua     only module that knows CLI args and the JSON envelope
    lua/folo/ui.lua      list + preview windows, selection, keymaps
    lua/folo/article.lua fetches article pages (curl, headless browser), see preview.ai.md
    lua/folo/render.lua  html -> text; own copy of the sample's module, not shared
    tests/cli_test.lua   headless CLI-layer self-check using tests/fake_folo.sh
    tests/article_test.lua  article fetching and UI self-check
    tests/fake_folo.sh, fake_curl.sh, fake_browser.sh  fixtures
```

## Upstream contract (read from folocli 0.0.5 source and client-sdk 0.3.95 types; not yet run with a real account)
- Global options: `--format json|table|plain` (default json), `--token`, `--api-url`, `--verbose`. Plugin passes `--format json` and never `--token`.
- Token order: `--token`, `FOLO_TOKEN`, stored config.
- Success: stdout `{ok:true,data,error:null}`. Failure: **stderr** `{ok:false,data:null,error:{code,message}}`, exit 1.
- `timeline [--view] [--limit] [--unread-only] [--cursor]` -> `{entries:[{read,view,from,feeds,entries:{id,title,url,author,publishedAt,...}}],nextCursor,hasNext}`; default limit 20.
- `entry get <id>` -> `{feeds,entries:{...,content}}` or null.
- `entry read <id>` -> `{content}` or null (readability).
- `entry mark-read <id>`, `entry mark-unread <id>`.
- `timeline --category <name>`: exact, case-sensitive match; unknown name returns an empty list.
- `collection list [--limit] [--cursor]` -> same shape as `timeline`.
- `subscription list [--view] [--category]` -> `{subscriptions:[{category,...}]}`; `category` may be null.

## Config
```lua
{
  cmd = { "folo" },        -- argv prefix; pending extensibility decision 1
  view = nil,              -- nil = CLI default
  page_size = nil,         -- nil = CLI default
  timeout_ms = 30000,
  render = "auto",         -- "auto" | "pandoc" | "strip"
  -- list_width, preview_debounce_ms, open_confirm_over, article, keymaps: see preview.ai.md
}
```

## CLI layer contract
- `M.run(args, cb(err, data))`: `vim.system(vim.list_extend(cmd, args), { text = true, timeout = timeout_ms })`; schedule cb on main loop.
- Never pass `--token`; child inherits env (`FOLO_TOKEN`) or CLI stored login.
- Errors, all routed to `err`: missing executable (install hint), timeout (`vim.system` code 124), non-zero exit, invalid JSON, `ok == false`. `UNAUTHORIZED` → hint to run login in a terminal.
- Parse stdout, or stderr when stdout is empty.
- Pass IDs and cursors as separate argv items; no shell.
- Entry field names mapped in one normalize function in `cli.lua`; UI never reads raw CLI fields.

## Commands
`:Folo` (timeline), `:FoloUnread` (`--unread-only`), `:FoloCategory [name]` (no argument: `vim.ui.select` over categories from `subscription list`), `:FoloStarred` (`collection list`).

## UI rules
- Layout, preview chain, selection and keymaps: [preview.ai.md](preview.ai.md).
- Reimplements the sample's patterns (scratch buffers, buffer-local keymaps); no shared module.
- Toggle read: update UI only after CLI success.
- Next page: append with `nextCursor`; notice when `hasNext` is false.
- One page request at a time per list; `r` reloads from the first page.
- Buffer lookup is an exact name match (`bufnr()` matches partially).

## Out of scope
Subscription management, collection add/remove, OPML, search, mark-all-read, sync with `rss/server`, direct HTTP to `api.folo.is`, copying Folo code (AGPL).

## Personal config
`~/.config/nvim/lua/plugins/folo.lua`: `dir` to `folo/nvim`, `cmd = { 'Folo', 'FoloUnread', 'FoloCategory', 'FoloStarred' }`.

## Verify
```sh
nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/cli_test.lua   # -> ok
nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/article_test.lua   # -> ok
```
- Test covers: parsing, read fallback, argv (no `--token`), UNAUTHORIZED, non-zero exit, invalid JSON, timeout, missing executable, CLI parsing and failures here; UI in `article_test.lua`.
- Manual, run by the user because the sandbox denies `~/.folo` and other home paths: `:Folo`, cursor move, `<CR>`, `m`, `]p`, `<Tab>`, `gx`, `R`.

## Extensibility decisions (confirmed)
1. CLI execution: default `{ "folo" }` (global install), `cmd` configurable; no `@latest`.
2. Accounts: single account.
3. Backend: UI depends only on `cli.lua`; no multi-backend interface.
