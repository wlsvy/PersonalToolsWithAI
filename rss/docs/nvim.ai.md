# nvim sample plugin (AI)

요약: [nvim.md](nvim.md)

## Files
```
nvim-sample/
  plugin/rss_sample.lua user commands only, lazy-require
  lua/rss_sample/init.lua      setup(opts), config merge (opts > env RSS_URL/RSS_TOKEN)
  lua/rss_sample/api.lua       curl via vim.system (async), vim.json.decode; one function per API v1 endpoint
  lua/rss_sample/ui.lua        buffers: feeds, entries, entry; keymaps
  lua/rss_sample/render.lua    html → text: pandoc if executable, else tag strip
  tests/render_test.lua strip() self-check (no server needed)
```
- api.lua is the only module that knows URLs/paths; base path `/api/v1` from config.
- Token/body passed to curl via stdin (`--config -`), never argv.
- External deps: `curl` required, `pandoc` optional.

## Commands
`:RssSample` (feeds), `:RssSampleUnread` (unread entries), `:RssSampleAdd <url>`, `:RssSampleRefresh [feedId]`.

## Keymaps (buffer-local)
- feeds: `<CR>` open entries, `r` refresh, `dd` delete (confirm), `q` close
- entries: `<CR>` open entry + mark read, `m` toggle read, `s` toggle star, `gx` open url (`vim.ui.open`), `]p` next page (cursor `next`), `q`
- entry: `filetype=markdown`, `gx`, `q`
- Keymaps overridable via `setup{ keymaps = {...} }`.

## Render
- `pandoc -f html -t gfm-raw_html --wrap=none` (drops leftover tags); fallback strips tags (`shortcut:` comment: no tables/links, install pandoc to upgrade).

## Verify
- `nvim --headless -u NONE --cmd "set rtp+=rss/nvim-sample" -l rss/nvim-sample/tests/render_test.lua` → `ok`
- `nvim --headless -u NONE --cmd "set rtp+=rss/nvim-sample" -c "lua require('rss_sample').setup{url='http://localhost:8080',token='dev'}" -c RssSample -c q` without errors; manual walkthrough against local server.
