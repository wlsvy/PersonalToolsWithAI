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

## Badges and colors

### Config
```lua
icons = {
  enabled = true,
  default = "\u{f09e}", -- no usable host
  palette = { "#e06c75", "#d19a66", "#98c379", "#56b6c2", "#61afef", "#c678dd", "#e5a50a", "#2aa198" },
  domains = {
    ["github.com"] = "\u{f09b}",                       -- string: icon, palette color
    ["youtube.com"] = { "\u{f16a}", color = "#ff4040" }, -- table: icon plus fixed color
  },
}
```
A domain value is a string, `{ icon, color = hex }`, or false. Existing string overrides keep working. A table with no `[1]` keeps the badge and only fixes the color.

### New default rows
All checked against `telescope-symbols.nvim` `nerd.json`. `nf-md-*` codepoints need Nerd Fonts v3.

| Host | Codepoint | Name | Color |
|---|---|---|---|
| `t.me` | `f2c6` | `nf-fa-telegram` | `#2aabee` |
| `linkedin.com` | `f0e1` | `nf-fa-linkedin` | `#3b82c4` |
| `instagram.com` | `f16d` | `nf-fa-instagram` | `#e1306c` |
| `facebook.com` | `f09a` | `nf-fa-facebook` | `#4c8bf5` |
| `stackoverflow.com` | `f16c` | `nf-fa-stack_overflow` | `#f48024` |
| `apple.com` | `f179` | `nf-fa-apple` | palette |
| `google.com` | `f1a0` | `nf-fa-google` | `#4285f4` |
| `microsoft.com` | `f0372` | `nf-md-microsoft` | `#00a4ef` |
| `wikipedia.org` | `f266` | `nf-fa-wikipedia_w` | palette |
| `spotify.com` | `f1bc` | `nf-fa-spotify` | `#1db954` |
| `twitch.tv` | `f1e8` | `nf-fa-twitch` | `#9146ff` |
| `gitlab.com` | `f296` | `nf-fa-gitlab` | `#fc6d26` |
| `steampowered.com` | `f1b6` | `nf-fa-steam` | palette |
| `amazon.com` | `f270` | `nf-fa-amazon` | `#ff9900` |
| `dev.to` | `f0d6e` | `nf-md-dev_to` | palette |
| `pinterest.com` | `f0d2` | `nf-fa-pinterest` | `#e60023` |
| `vimeo.com` | `f27d` | `nf-fa-vimeo` | `#1ab7ea` |
| `producthunt.com` | `f288` | `nf-fa-product_hunt` | `#da552f` |
| `discord.com` | `f066f` | `nf-md-discord` | `#5865f2` |
| `playstation.com` | `e230` | `nf-fae-playstation` | `#2e6db4` |

Existing rows gain colors: `youtube.com` `#ff4040`, `reddit.com` `#ff4500`, `news.ycombinator.com` `#ff6600`, `medium.com` none, `substack.com` `#ff6719`, `arxiv.org` `#b31b1b`, `x.com`/`twitter.com` `#1d9bf0`. `github.com` stays palette; its brand color is unreadable on dark themes.

No bluesky, threads, openai or epic glyph exists in the table, so those hosts get badges. Do not add the user's own feeds (`hankyung.com`, ...) as defaults.

### `icons.lua`
`for_entry(e)` returns `icon, color`:
1. Walk host and parents as today. A string or table with `[1]` is the icon; `color` comes from the table.
2. No icon: `badge(host)`; no badge: `default`.
3. No color: `palette[(sum of host bytes) % #palette + 1]`, hashing the host as written in the entry. No host: nil color (default icon stays plain).

`badge(host)`:
- nil when the host has no dot, is all digits and dots, or has no match below. Host comes from feeds, so only `%w` reaches the row.
- Label: second-to-last. When the last label has 2 chars, the second-to-last has at most 3 and there are 3+ labels (`bbc.co.uk`), use third-to-last.
- `label:match("^%w%w?")`, uppercased. `t.me`-like one-char labels stay one char.
- Comment: `shortcut: no public suffix list, upgrade if badges for ccTLD hosts look wrong`.

### `ui.lua` `redraw`
- Pad the icon to 2 display cells with `strdisplaywidth`; wider values get no padding. Row: `icon .. pad .. " " .. date`.
- Namespace `folo_icons`: clear it on redraw. For each entry row with a color, `nvim_buf_set_extmark(buf, ns, row, col, { end_col = col + #icon, hl_group = group })`. `col` is the byte length of the row prefix before the icon; `set_lines` must run first.
- Group: `"FoloIcon" .. hex` without `#`. Call `nvim_set_hl(0, group, { fg = color })` during redraw for each color used, so a colorscheme change recovers at the next redraw.
- Validate the color with `^#%x%x%x%x%x%x$`; skip the highlight otherwise. A bad user value must not raise in redraw.

### Tests
- `icons_test.lua`: badges `openai.com` → `OP`, `science.nasa.gov` → `NA`, `bbc.co.uk` → `BB`, `127.0.0.1` / `localhost` / `javascript:` → default; `reddit.com = false` → `RE` (was default); `unknown.org` → `UN`. Color: table value fixed; same host stable; string gets a palette member; no host nil; bad hex does not raise.
- `stars_test.lua:83`, `article_test.lua:161`: `" *   \u{f09e}  2026-01-02  F1  first line"` (`https://x/1` has no dotted host, so default plus one pad).
- UI: a row with a colored icon has one extmark on the icon's bytes; `nvim_buf_get_extmarks` after redraw shows no duplicates.
- Run all five tests.

## Config (`init.lua` defaults)
Shape and glyphs are in "Badges and colors" and "Nerd Font glyphs" above. Host key: lowercase, no "www.".
- Merged by the existing `vim.tbl_deep_extend("force", ...)`, so user keys add or override; `false` falls through to the parent domain, then the badge. `{ color = hex }` over a table default keeps its icon; over a string default it gives the badge.
- `icons.enabled = false` → no icon column.

## Lookup (new `lua/folo/icons.lua`, `M.for_entry(e)`)
1. URL = `e.site ~= "" and e.site or e.url`.
2. Host = match `^%a[%w+.-]*://([^/?#:@]+)` (ignores userinfo-less ports via `:`), lowercase, strip leading `www.`.
3. Try host, then drop the leftmost label repeatedly (`a.b.github.com` → `b.github.com` → `github.com`); stop before a single label.
4. First non-false value wins; else the badge; else `default`.
- No host (empty / `javascript:` / nil) → `default`.

## UI
- `ui.lua` `redraw`: line becomes `selected .. mark .. " " .. icon .. " " .. date ...` when enabled; otherwise unchanged format.
- Only the list. Preview header, child rows unchanged.
- The icon color extmark is the only code that depends on byte columns in the list.

## Tests
- `tests/icons_test.lua`: lookup cases + `site` from fake `--category News` item (`siteUrl` added in `fake_folo.sh`).
- `tests/article_test.lua`: list line now has the icon.
- Run all four existing tests.

## Out of scope
Favicon download/render, inline images, preview icon, feed-title matching, emoji/glyph mode switch, an option to turn colors off, cterm colors.
