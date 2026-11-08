# Feed icons (AI)

요약: [icons.md](icons.md)

Status: implemented. Test: `tests/icons_test.lua` (`enabled=false` path not covered; one ternary in `ui.lua` redraw).

## Data
- `cli.lua` `normalize`: add `site = feed.siteUrl or ""`. `siteUrl` is in client-sdk feed types (`FeedDiscoveryResult.siteUrl: string | null`); not yet confirmed in real `timeline` output.
- UI still reads only normalized fields.

## Config (`init.lua` defaults)
```lua
icons = {
  enabled = true,
  default = "📰",           -- unmatched host or no URL
  domains = {               -- key: lowercase host, no "www."; value: string, or false to drop a default
    ["github.com"] = "🐙",
    ["youtube.com"] = "📺",
    ["reddit.com"] = "👽",
    ["news.ycombinator.com"] = "🟧",
    ["medium.com"] = "✍️",
    ["substack.com"] = "📮",
    ["arxiv.org"] = "📄",
    ["x.com"] = "🐦",
    ["twitter.com"] = "🐦",
  },
},
```
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
Favicon download/render, preview icon, feed-title matching, Nerd Font glyphs.
