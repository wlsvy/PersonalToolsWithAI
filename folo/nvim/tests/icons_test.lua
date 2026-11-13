-- Run: nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/icons_test.lua
local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.env.FAKE_FOLO_LOG = vim.fn.tempname()

local folo = require("folo")
local cli = require("folo.cli")
local icons = require("folo.icons")
folo.setup({
  cmd = { dir .. "/fake_folo.sh" },
  render = "strip",
  list_width = 30,
  preview_debounce_ms = 10,
  lazy_load_margin = 0,
  article = { auto_fetch = false },
  icons = {
    domains = {
      ["example.com"] = "🦊",
      ["reddit.com"] = false,
      ["fixed.org"] = { "F", color = "#123456" },
      ["tinted.org"] = { color = "#112233" },
    },
  },
})
vim.notify = function() end

local function eq(got, want)
  assert(vim.deep_equal(got, want), vim.inspect(got) .. " ~= " .. vim.inspect(want))
end

local function icon(site, url)
  return icons.for_entry({ site = site or "", url = url or "" })
end

-- Lookup: site wins over URL, www/case/port/userinfo stripped, subdomains inherit.
eq(icon("https://github.com"), "\u{f09b}")
eq(icon("", "https://WWW.YouTube.com/watch?v=1"), "\u{f16a}")
eq(icon("https://example.com", "https://github.com/x"), "🦊")
eq(icon("", "https://a.b.example.com:8443/x"), "🦊")
eq(icon("", "https://user@news.ycombinator.com/item"), "\u{f1d4}")
-- Hosts outside the table get a badge; false drops a default.
eq(icon("", "https://reddit.com/r/x"), "RE")
eq(icon("", "https://unknown.org/"), "UN")
eq(icon("", "https://openai.com/"), "OP")
eq(icon("", "https://science.nasa.gov/"), "NA")
eq(icon("", "https://www.bbc.co.uk/news"), "BB")
eq(icon("", "https://a.1x.com/"), "1X")
eq(icon("", "https://z.me/"), "Z")
eq(icon("", "https://_x.org/"), "\u{f09e}")
-- Empty, non-web, undotted and numeric hosts fall back.
eq(icon("", ""), "\u{f09e}")
eq(icon("", "javascript:alert(1)"), "\u{f09e}")
eq(icon("", "https://localhost/"), "\u{f09e}")
eq(icon("", "http://127.0.0.1:8080/"), "\u{f09e}")

-- Colors: a table fixes the color, with or without its own icon; the rest use the palette.
local function both(url)
  return { icons.for_entry({ site = "", url = url }) }
end
local palette = folo.get_config().icons.palette
eq(both("https://a.fixed.org/"), { "F", "#123456" })
eq(both("https://tinted.org/"), { "TI", "#112233" })
eq(both("https://www.youtube.com/"), { "\u{f16a}", "#ff4040" })
eq(both(""), { "\u{f09e}" })
for _, url in ipairs({ "https://github.com/", "https://openai.com/", "https://unknown.org/" }) do
  local got = both(url)
  assert(vim.tbl_contains(palette, got[2]), vim.inspect(got))
  eq(both(url), got)
end

-- CLI maps feeds.siteUrl to entry.site.
local result
cli.timeline({ category = "News" }, function(err, page)
  result = { err, page }
end)
assert(vim.wait(3000, function()
  return result ~= nil
end), "timed out")
eq(result[1], nil)
eq(result[2].entries[1].site, "https://www.GitHub.com/blog")
eq(icons.for_entry(result[2].entries[1]), "\u{f09b}")

-- UI: the icon column is two cells and only the icon's bytes are colored, once per redraw.
vim.cmd("source " .. dir .. "/../plugin/folo.lua")
require("folo.ui").timeline({ category = "News" }, "category/News")
local list = vim.api.nvim_get_current_buf()
local function row()
  return vim.api.nvim_buf_get_lines(list, 0, 1, false)[1] or ""
end
local function marks()
  local ns = vim.api.nvim_get_namespaces().folo_icons
  return vim.api.nvim_buf_get_extmarks(list, ns, 0, -1, { details = true })
end
assert(vim.wait(3000, function()
  return row():find("news item", 1, true) ~= nil
end), "list did not load")
eq(row(), " *   \u{f09b}  2026-03-01  F4  news item")
local function press(keys)
  vim.api.nvim_feedkeys(keys, "x", false)
end
local function check_mark()
  local all = marks()
  eq(#all, 1)
  eq({ all[1][2], all[1][3], all[1][4].end_row or 0, all[1][4].end_col }, { 0, 5, 0, 8 })
  local fg = vim.api.nvim_get_hl(0, { name = all[1][4].hl_group }).fg
  assert(vim.tbl_contains(palette, ("#%06x"):format(fg)), all[1][4].hl_group)
end
check_mark()
press("m")
assert(vim.wait(3000, function()
  return row():sub(2, 2) == " "
end), "read toggle did not redraw")
check_mark()

-- A bad color skips the highlight instead of breaking the redraw; two-cell icons get no padding.
folo.config.icons.domains["github.com"] = { "ZZ", color = "nope" }
press("m")
assert(vim.wait(3000, function()
  return row():sub(2, 2) == "*"
end), "bad color broke the redraw")
eq(row(), " *   ZZ 2026-03-01  F4  news item")
eq(#marks(), 0)

print("ok")
