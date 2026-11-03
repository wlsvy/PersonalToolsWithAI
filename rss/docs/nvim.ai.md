# nvim plugin (AI)

요약: [nvim.md](nvim.md)

## Files
```
nvim/
  plugin/rss.lua        user commands only, lazy-require
  lua/rss/init.lua      setup(opts), config merge (opts > env RSS_URL/RSS_TOKEN)
  lua/rss/api.lua       curl via vim.system (async), vim.json.decode; one function per API v1 endpoint
  lua/rss/ui.lua        buffers: feeds, entries, entry; keymaps
  lua/rss/render.lua    html → text: pandoc if executable, else tag strip
```
- api.lua is the only module that knows URLs/paths; base path `/api/v1` from config.
- External deps: `curl` required, `pandoc` optional.

## Commands
`:Rss` (feeds), `:RssUnread` (unread entries), `:RssAdd <url>`, `:RssRefresh [feedId]`.

## Keymaps (buffer-local)
- feeds: `<CR>` open entries, `r` refresh, `dd` delete (confirm), `q` close
- entries: `<CR>` open entry + mark read, `m` toggle read, `s` toggle star, `gx` open url (`vim.ui.open`), `]p` next page (cursor `next`), `q`
- entry: `filetype=markdown`, `gx`, `q`
- Keymaps overridable via `setup{ keymaps = {...} }`.

## Render
- `pandoc -f html -t gfm`; fallback strips tags (`shortcut:` comment: no tables/links, install pandoc to upgrade).

## Verify
`nvim --headless -u NONE --cmd "set rtp+=rss/nvim" -c "lua require('rss').setup{url='http://localhost:8080',token='dev'}" -c Rss -c q` without errors; manual walkthrough against local server.
