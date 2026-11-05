# RSS nvim plugin → sample rename (AI)

요약: [sample-rename.md](sample-rename.md)

Status: implemented.

## Mapping
| Old | New |
|---|---|
| `rss/nvim/` | `rss/nvim-sample/` |
| `lua/rss/` | `lua/rss_sample/` |
| `plugin/rss.lua` | `plugin/rss_sample.lua` |
| `require("rss")`, `require("rss.*")` | `require("rss_sample")`, `require("rss_sample.*")` |
| `vim.g.loaded_rss` | `vim.g.loaded_rss_sample` |
| `:Rss`, `:RssUnread`, `:RssAdd`, `:RssRefresh` | `:RssSample`, `:RssSampleUnread`, `:RssSampleAdd`, `:RssSampleRefresh` |
| notify prefix `rss:` | `rss_sample:` |
| `~/.config/nvim/lua/plugins/rss.lua` | `~/.config/nvim/lua/plugins/rss_sample.lua` (`dir`, `name`, `cmd`) |

## Keep
- Env `RSS_URL`, `RSS_TOKEN`: server contract.
- Server, web, API, behaviour, keymaps.

## Files to update
- All of `rss/nvim/**` incl. `tests/render_test.lua`.
- `rss/README.md`, `rss/docs/nvim.md`, `rss/docs/nvim.ai.md`, `rss/docs/config.md`, `rss/docs/config.ai.md`, `rss/docs/plan.md`, `rss/docs/plan.ai.md` (grep each; mark plugin as a learning sample).
- Use `git mv`; no compatibility aliases.

## Verify
```sh
grep -rnE 'require\("rss[".]|:Rss[A-Z ]|rss/nvim/' rss --include='*' --exclude-dir=node_modules --exclude-dir=dist
nvim --headless -u NONE --cmd "set rtp+=rss/nvim-sample" -l rss/nvim-sample/tests/render_test.lua   # -> ok
nvim --headless -u NONE --cmd "set rtp+=rss/nvim-sample" -c "runtime plugin/rss_sample.lua" -c "command RssSample" -c "qa!"
```
Manual: restart Neovim, confirm lazy.nvim loads `:RssSample`.
