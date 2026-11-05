-- Run: nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/cli_test.lua
local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local log = vim.fn.tempname()
vim.env.FAKE_FOLO_LOG = log

local folo = require("folo")
local cli = require("folo.cli")
folo.setup({ cmd = { dir .. "/fake_folo.sh" }, render = "strip", timeout_ms = 500 })

-- Waits for an async call: fn(done) passes its callback args back to the caller.
local function await(fn)
  local result
  fn(function(...)
    result = { n = select("#", ...), ... }
  end)
  assert(vim.wait(3000, function()
    return result ~= nil
  end), "timed out waiting for callback")
  return unpack(result, 1, result.n)
end

local function eq(got, want)
  assert(vim.deep_equal(got, want), vim.inspect(got) .. " ~= " .. vim.inspect(want))
end

local function mode(m)
  vim.env.FAKE_FOLO_MODE = m
end

local function last_args()
  local lines = vim.fn.readfile(log)
  return lines[#lines]
end

-- Success paths
local err, page = await(function(cb)
  cli.timeline({ unread = true }, cb)
end)
eq(err, nil)
eq(#page.entries, 2)
eq(page.next, "2026-01-01T00:00:00Z")
eq({ page.entries[1].id, page.entries[1].read, page.entries[1].feed }, { "1", false, "F1" })
eq({ page.entries[2].url, page.entries[2].feed }, { "", "" })
eq(last_args(), "--format json timeline --unread-only")
assert(not vim.fn.readfile(log)[1]:find("--token", 1, true))

err, page = await(function(cb)
  cli.timeline({ cursor = "2026-01-01" }, cb)
end)
eq({ err, #page.entries, page.next }, { nil, 1, nil })

local e
err, e = await(function(cb)
  cli.entry("1", cb)
end)
eq({ err, e.content }, { nil, "<p>body</p>" })

err, e = await(function(cb)
  cli.entry("2", cb)
end)
eq({ err, e.content }, { nil, "<p>readable</p>" })

err = await(function(cb)
  cli.entry("404", cb)
end)
assert(err:find("not found", 1, true), err)

err = await(function(cb)
  cli.set_read("1", false, cb)
end)
eq(err, nil)
eq(last_args(), "--format json entry mark-unread 1")

-- Failure paths
mode("unauthorized")
err = await(function(cb)
  cli.run({ "timeline" }, cb)
end)
assert(err:find("UNAUTHORIZED", 1, true) and err:find("folo login", 1, true), err)

mode("crash")
err = await(function(cb)
  cli.run({ "timeline" }, cb)
end)
eq(err, "exit 3: boom")

mode("badjson")
err = await(function(cb)
  cli.run({ "timeline" }, cb)
end)
eq(err, "invalid JSON from CLI")

mode("slow")
err = await(function(cb)
  cli.run({ "timeline" }, cb)
end)
eq(err, "timed out")
mode("")

folo.setup({ cmd = { dir .. "/does-not-exist" } })
err = await(function(cb)
  cli.run({ "timeline" }, cb)
end)
assert(err:find("cannot run", 1, true), err)

-- UI: list, read toggle, paging, failure keeps state
folo.setup({ cmd = { dir .. "/fake_folo.sh" }, render = "strip", timeout_ms = 500 })
vim.cmd("source " .. dir .. "/../plugin/folo.lua")
vim.cmd("Folo")
local buf = vim.api.nvim_get_current_buf()
local function lines()
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end
local function wait_line(n, pattern)
  assert(vim.wait(3000, function()
    local l = lines()[n]
    return l ~= nil and l:find(pattern) ~= nil
  end), "line " .. n .. " never matched " .. pattern .. ": " .. vim.inspect(lines()))
end
local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end
wait_line(1, "^%* 2026%-01%-02  F1  first line$")
eq(#lines(), 2)

mode("crash")
vim.notify = function() end
press("m")
vim.wait(300)
eq(lines()[1]:sub(1, 1), "*")
mode("")
press("m")
wait_line(1, "^  2026")

press("]p")
wait_line(3, "third")

vim.api.nvim_win_set_cursor(0, { 2, 0 })
press("<CR>")
assert(vim.wait(3000, function()
  return vim.api.nvim_buf_get_name(0) == "folo://entry/2"
end), "entry buffer did not open")
eq(vim.api.nvim_buf_get_lines(0, -2, -1, false), { "readable" })

-- R replaces the body and keeps the header; nothing extracted keeps the body.
local function open_entry(id)
  require("folo.ui").entry(id)
  assert(vim.wait(3000, function()
    return vim.api.nvim_buf_get_name(0) == "folo://entry/" .. id
  end), "entry " .. id .. " did not open")
end
local function last_line()
  return vim.api.nvim_buf_get_lines(0, -2, -1, false)[1]
end
open_entry("1")
eq(last_line(), "body")
press("R")
assert(vim.wait(3000, function()
  return last_line() == "full article"
end), "readability did not replace body: " .. last_line())
eq(vim.api.nvim_buf_get_lines(0, 0, 1, false), { "# first" })

open_entry("3")
press("R")
vim.wait(300)
eq(last_line(), "short")

-- Categories: unique, sorted, nulls dropped; picking opens that category.
local names
err, names = await(function(cb)
  cli.categories(cb)
end)
eq({ err, names }, { nil, { "AI", "News" } })

local offered
vim.ui.select = function(items, _, on_choice)
  offered = items
  on_choice("News")
end
vim.cmd("FoloCategory")
assert(vim.wait(3000, function()
  return vim.api.nvim_buf_get_name(0) == "folo://timeline/category/News"
end), "picked category did not open")
eq(offered, { "AI", "News" })
assert(vim.wait(3000, function()
  return (vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""):find("news item", 1, true) ~= nil
end), "category entries did not load")
eq(last_args(), "--format json timeline --category News")

-- A name that is a prefix of an open category gets its own buffer.
vim.cmd("FoloCategory New")
eq(vim.api.nvim_buf_get_name(0), "folo://timeline/category/New")
eq(vim.tbl_contains(vim.tbl_map(vim.api.nvim_buf_get_name, vim.api.nvim_list_bufs()), "folo://timeline/category/News"), true)

-- Dismissing the picker opens nothing.
local before = vim.api.nvim_get_current_buf()
vim.ui.select = function(_, _, on_choice)
  on_choice(nil)
  offered = "dismissed"
end
vim.cmd("FoloCategory")
assert(vim.wait(3000, function()
  return offered == "dismissed"
end))
eq(vim.api.nvim_get_current_buf(), before)

vim.cmd("FoloStarred")
eq(vim.api.nvim_buf_get_name(0), "folo://timeline/starred")
assert(vim.wait(3000, function()
  return (vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""):find("saved", 1, true) ~= nil
end), "starred entries did not load")
eq(last_args(), "--format json collection list")

print("ok")
