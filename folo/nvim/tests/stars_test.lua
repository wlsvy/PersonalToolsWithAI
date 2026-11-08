-- Run: nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/stars_test.lua
local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local log = vim.fn.tempname()
vim.env.FAKE_FOLO_LOG = log

local folo = require("folo")
local cli = require("folo.cli")
folo.setup({
  cmd = { dir .. "/fake_folo.sh" },
  render = "strip",
  timeout_ms = 2000,
  list_width = 30,
  preview_debounce_ms = 10,
  lazy_load_margin = 0,
  article = { auto_fetch = false },
  ai = { dir = vim.fn.tempname() },
})

local function eq(got, want)
  assert(vim.deep_equal(got, want), vim.inspect(got) .. " ~= " .. vim.inspect(want))
end
local function wait(fn, what)
  assert(vim.wait(4000, fn, 10), what)
end
local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end
local function logged(text)
  for _, line in ipairs(vim.fn.readfile(log)) do
    if line:find(text, 1, true) then
      return true
    end
  end
  return false
end
local notices = {}
vim.notify = function(msg)
  table.insert(notices, msg)
end

-- CLI: the collection list is starred by definition; star calls are separate argv items.
local result
cli.collection({}, function(err, page)
  result = { err, page }
end)
wait(function()
  return result ~= nil
end, "collection timed out")
eq({ result[1], result[2].entries[1].starred }, { nil, true })
-- The collection pages by star time, not by the publish time the CLI offers as a cursor.
eq(result[2].next, "2026-02-05T00:00:00Z")
local cursor = result[2].next
result = nil
cli.collection({ cursor = cursor }, function(err, page)
  result = { err, page }
end)
wait(function()
  return result ~= nil
end, "collection page 2 timed out")
assert(logged("collection list --cursor 2026-02-05T00:00:00Z"), "star time cursor argv")
eq({ result[1], result[2].entries[1].id, result[2].entries[1].starred, result[2].next }, { nil, "10", true, nil })
result = nil
cli.set_starred("7", true, function(err)
  result = { err }
end)
wait(function()
  return result ~= nil
end, "add timed out")
eq(result[1], nil)
assert(logged("--format json collection add 7"), "add argv")

vim.cmd("source " .. dir .. "/../plugin/folo.lua")

-- UI: S toggles the current entry; the row stays when unstarred.
vim.cmd("Folo")
local list = vim.api.nvim_get_current_buf()
local function lines()
  return vim.api.nvim_buf_get_lines(list, 0, -1, false)
end
wait(function()
  return (lines()[2] or ""):find("second", 1, true) ~= nil
end, "list did not load")
eq(lines()[1], " *   \u{f09e} 2026-01-02  F1  first line")
assert(lines()[2]:find("\u{f005}", 1, true), lines()[2])

vim.api.nvim_win_set_cursor(0, { 1, 0 })
press("S")
wait(function()
  return lines()[1]:find("\u{f005}", 1, true) ~= nil
end, "star not shown")
assert(logged("collection add 1"), "add 1")
press("S")
wait(function()
  return not lines()[1]:find("\u{f005}", 1, true)
end, "star not removed")
assert(logged("collection remove 1"), "remove 1")
eq(#lines(), 2)

-- Selection with one unstarred entry stars only that one, then clears the selection.
vim.fn.writefile({}, log)
press("<Tab>")
press("<Tab>")
press("S")
wait(function()
  return lines()[1]:find("\u{f005}", 1, true) ~= nil
end, "selection not starred")
assert(logged("collection add 1") and not logged("collection add 2"), vim.inspect(vim.fn.readfile(log)))
eq({ lines()[1]:sub(1, 1), lines()[2]:sub(1, 1) }, { " ", " " })

-- A failed call leaves the star in place.
vim.env.FAKE_FOLO_MODE = "crash"
vim.api.nvim_win_set_cursor(0, { 1, 0 })
press("S")
wait(function()
  return #notices > 0 and notices[#notices]:find("exit 3", 1, true) ~= nil
end, "error not reported")
assert(lines()[1]:find("\u{f005}", 1, true), lines()[1])
vim.env.FAKE_FOLO_MODE = nil

-- m on a selection: any unread entry marks all read, calling only what changes, then clears it.
local function read_marks()
  return { lines()[1]:sub(2, 2), lines()[2]:sub(2, 2) }
end
local function select_both()
  vim.fn.writefile({}, log)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("<Tab>")
  press("<Tab>")
end
select_both()
press("m")
wait(function()
  return lines()[1]:sub(2, 2) == " "
end, "selection not marked read")
assert(logged("entry mark-read 1") and not logged("entry mark-read 2"), vim.inspect(vim.fn.readfile(log)))
eq({ lines()[1]:sub(1, 1), lines()[2]:sub(1, 1) }, { " ", " " })

-- All read: marks all unread.
select_both()
press("m")
wait(function()
  return vim.deep_equal(read_marks(), { "*", "*" })
end, "selection not marked unread")
assert(logged("entry mark-unread 1") and logged("entry mark-unread 2"), vim.inspect(vim.fn.readfile(log)))

-- Failed calls leave the read state in place.
select_both()
local before = #notices
vim.env.FAKE_FOLO_MODE = "crash"
press("m")
wait(function()
  return #notices >= before + 2
end, "read errors not reported")
vim.wait(100)
eq(read_marks(), { "*", "*" })
vim.env.FAKE_FOLO_MODE = nil

-- No selection: only the current entry changes.
vim.fn.writefile({}, log)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
press("m")
wait(function()
  return lines()[1]:sub(2, 2) == " "
end, "current entry not marked read")
assert(logged("entry mark-read 1") and not logged("entry mark-read 2"), vim.inspect(vim.fn.readfile(log)))
eq(read_marks(), { " ", "*" })

-- Lazy loading: off at 0; on, moving near the end loads the next page once, deduplicated.
local function move_to(row)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
end
vim.fn.writefile({}, log)
move_to(2)
vim.wait(100)
assert(not logged("--cursor"), "loaded with margin 0")
folo.config.lazy_load_margin = 5
move_to(1)
wait(function()
  return #lines() == 3
end, "next page did not load")
assert(logged("--cursor 2026-01-01"), "cursor argv")
assert(lines()[3]:find("third", 1, true), lines()[3])

-- Help shows page size, order and the live paging rule.
press("?")
local text
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
  end
end
for _, want in ipairs({ "20 (CLI default)", "newest first", "by star time", "within 5 rows", "\u{f005} starred", "Star or unstar" }) do
  assert(text and text:find(want, 1, true), want .. " missing in:\n" .. tostring(text))
end
press("?")

print("ok")
