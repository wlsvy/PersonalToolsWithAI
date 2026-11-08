-- Run: nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/icons_test.lua
local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.env.FAKE_FOLO_LOG = vim.fn.tempname()

local folo = require("folo")
local cli = require("folo.cli")
local icons = require("folo.icons")
folo.setup({
  cmd = { dir .. "/fake_folo.sh" },
  icons = { domains = { ["example.com"] = "🦊", ["reddit.com"] = false } },
})

local function eq(got, want)
  assert(vim.deep_equal(got, want), vim.inspect(got) .. " ~= " .. vim.inspect(want))
end

local function icon(site, url)
  return icons.for_entry({ site = site or "", url = url or "" })
end

-- Lookup: site wins over URL, www/case/port/userinfo stripped, subdomains inherit.
eq(icon("https://github.com"), "🐙")
eq(icon("", "https://WWW.YouTube.com/watch?v=1"), "📺")
eq(icon("https://example.com", "https://github.com/x"), "🦊")
eq(icon("", "https://a.b.example.com:8443/x"), "🦊")
eq(icon("", "https://user@news.ycombinator.com/item"), "🟧")
-- false drops a default; unknown, empty and non-web URLs fall back.
eq(icon("", "https://reddit.com/r/x"), "📰")
eq(icon("", "https://unknown.org/"), "📰")
eq(icon("", ""), "📰")
eq(icon("", "javascript:alert(1)"), "📰")
eq(icon("", "https://localhost/"), "📰")

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
eq(icons.for_entry(result[2].entries[1]), "🐙")

print("ok")
