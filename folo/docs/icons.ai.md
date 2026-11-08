# Feed icons (AI)

요약: [icons.md](icons.md)

Status: implemented. Test: `tests/icons_test.lua` (`enabled=false` path not covered; one ternary in `ui.lua` redraw).

## Nerd Font glyphs
Replaced the emoji defaults. Lookup, merge and `false` semantics are unchanged. No mode option and no dependency (`nvim-web-devicons` maps file types, not sites). A terminal without the font shows blanks or broken characters; the user accepted that.

Write glyphs as `"\u{xxxx}"` plus a name comment, so the source survives editors and tools without the font. `vim.system` already implies Neovim 0.10; `\u{}` needs LuaJIT, which official builds use.

| Key | Codepoint | Nerd Font name | Note |
|---|---|---|---|
| `default` | `f09e` | `nf-fa-rss` | |
| `STAR` in `ui.lua` | `f005` | `nf-fa-star` | constant, not configurable |
| `github.com` | `f09b` | `nf-fa-github` | |
| `youtube.com` | `f16a` | `nf-fa-youtube_play` | |
| `reddit.com` | `f281` | `nf-fa-reddit_alien` | |
| `news.ycombinator.com` | `f1d4` | `nf-fa-hacker_news` | |
| `medium.com` | `f23a` | `nf-fa-medium` | |
| `substack.com` | `f0e0` | `nf-fa-envelope` | no logo; newsletter |
| `arxiv.org` | `f0f6` | `nf-fa-file_text_o` | no logo; paper |
| `x.com`, `twitter.com` | `f099` | `nf-fa-twitter` | |

Font Awesome range only. Codepoints checked against `telescope-symbols.nvim` `nerd.json`.

`ui.lua`:
- `redraw`: `star = e.starred and STAR or " "` (blank is one cell, the glyph's width in Neovim).
- `icons.enabled = false` hides only the site column. The star always shows, since it carries state.

Tests: expected values use `\u{}`. The `["example.com"] = "🦊"` override in `icons_test.lua` stays, which proves a site emoji still works.

## Data
- `cli.lua` `normalize`: add `site = feed.siteUrl or ""`. `siteUrl` is in client-sdk feed types (`FeedDiscoveryResult.siteUrl: string | null`); not yet confirmed in real `timeline` output.
- UI still reads only normalized fields.

## Config (`init.lua` defaults)
`icons = { enabled = true, default = <glyph>, domains = { [host] = <glyph> } }`. Host key: lowercase, no "www."; value: any string, or false to drop a default. Glyphs are in the table above.
- Merged by the existing `vim.tbl_deep_extend("force", ...)`, so user keys add or override; `false` falls through to parent domain / `default`.
- `icons.enabled = false` → no icon column.

## Lookup (new `lua/folo/icons.lua`, `M.for_entry(e)`)
1. URL = `e.site ~= "" and e.site or e.url`.
2. Host = match `^%a[%w+.-]*://([^/?#:@]+)` (ignores userinfo-less ports via `:`), lowercase, strip leading `www.`.
3. Try host, then drop the leftmost label repeatedly (`a.b.github.com` → `b.github.com` → `github.com`); stop before a single label.
4. First non-false string wins; else `default`.
- No host (empty / `javascript:` / nil) → `default`.

## UI
- `ui.lua` `redraw`: line becomes `selected .. mark .. " " .. icon .. " " .. date ...` when enabled; otherwise unchanged format.
- Only the list. Preview header, child rows unchanged.
- No highlight/extmark code depends on byte columns in the list (checked), so no offset fixes.

## Tests
- `tests/icons_test.lua`: lookup cases + `site` from fake `--category News` item (`siteUrl` added in `fake_folo.sh`).
- `tests/article_test.lua`: list line now has the icon.
- Run all four existing tests.

## Out of scope
Favicon download/render, preview icon, feed-title matching, per-site highlight colors, emoji/glyph mode switch.
