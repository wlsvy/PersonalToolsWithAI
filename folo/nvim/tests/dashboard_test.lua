-- Run: nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/dashboard_test.lua
local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local log = vim.fn.tempname()
vim.env.FAKE_FOLO_LOG = log

local folo = require("folo")
local cli = require("folo.cli")
local ui = require("folo.ui")
vim.cmd.source(dir .. "/../plugin/folo.lua") -- -u NONE skips plugin/
folo.setup({
  cmd = { dir .. "/fake_folo.sh" },
  view = "articles",
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
local function find_line(text)
  for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find(text, 1, true) then
      return i
    end
  end
end

-- CLI: only the configured view counts, and total follows the kept items.
local result
cli.unread(function(err, data)
  result = { err, data }
end)
wait(function()
  return result ~= nil
end, "unread timed out")
eq({ result[1], result[2].total, #result[2].items }, { nil, 16, 4 })

-- One tab named after the dashboard; the second :Folo reuses it.
ui.dashboard()
wait(function()
  return find_line("Nothing") or find_line("Uncategorized")
end, "dashboard did not draw")
eq(vim.api.nvim_buf_get_name(0):match("Folo Dashboard$") ~= nil, true)
eq(vim.t.tabname, "Folo Dashboard")
local tabs = #vim.api.nvim_list_tabpages()
eq(tabs, 2)
-- The header is a one-line window spanning the top; the active panel's badge is filled.
local function header()
  local hbuf = vim.fn.bufnr("folo://header")
  local hwin = vim.fn.bufwinid(hbuf)
  assert(hwin ~= -1, "no header window")
  eq(vim.fn.winlayout()[2][1], { "leaf", hwin }) -- topmost in the column
  eq(vim.api.nvim_win_get_width(hwin), vim.o.columns)
  local active = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(hbuf, -1, 0, -1, { details = true })) do
    if m[4].hl_group:find("^FoloBadgeOn") then
      table.insert(active, vim.api.nvim_buf_get_text(hbuf, m[2], m[3], m[2], m[4].end_col, {})[1])
    end
  end
  return vim.api.nvim_buf_get_lines(hbuf, 0, 1, false)[1], active
end
local head, active = header()
assert(head:find("\u{e0b6} Timeline (T) \u{e0b4}", 1, true), head)
eq(active, { " Dashboard (D) " })

-- Groups by count desc, feeds by count desc, empty category last here.
local news, ai_row, big, small, loose = find_line("News  "), find_line("AI  "), find_line("Big"), find_line("Small"), find_line("Uncategorized")
assert(news < ai_row and ai_row < big and big < small and small < loose, vim.inspect({ news, ai_row, big, small, loose }))
assert(not find_line("Social"), "other view leaked in")
assert(find_line("Unread  \u{e0b6} 16 \u{e0b4}"), "total badge")

-- <CR> on a feed opens its unread entries in the dashboard tab.
vim.api.nvim_win_set_cursor(0, { big, 0 })
press("<CR>")
wait(function()
  return logged("timeline --view 0 --feed f2 --unread-only") or logged("--feed f2")
end, "feed timeline not requested")
assert(logged("--unread-only"), "not unread only")
eq(#vim.api.nvim_list_tabpages(), tabs)
eq(vim.t.folo_dashboard, true)

-- q on the list lands back on the dashboard.
wait(function()
  return vim.bo.filetype == "folo-timeline"
end, "list not shown")
eq(select(2, header()), { " Unread (U) " })
press("q")
eq(vim.api.nvim_buf_get_name(0):match("Folo Dashboard$") ~= nil, true)
eq(#vim.api.nvim_tabpage_list_wins(0), 2) -- header + dashboard

-- From another tab, :Folo jumps back instead of making a new tab.
vim.cmd("tabprevious")
vim.cmd("Folo")
eq(#vim.api.nvim_list_tabpages(), tabs)
eq(vim.t.folo_dashboard, true)

-- <CR> on a category header opens that category's unread entries.
wait(function()
  return find_line("News  ") ~= nil
end, "redraw")
vim.api.nvim_win_set_cursor(0, { find_line("News  "), 0 })
press("<CR>")
wait(function()
  return logged("--category News")
end, "category timeline not requested")

-- Commands from another tab land in the Folo tab, replacing the panel.
vim.cmd("tabnext 1")
vim.cmd("FoloStarred")
eq(#vim.api.nvim_list_tabpages(), tabs)
eq(vim.t.folo_dashboard, true)
wait(function()
  return vim.bo.filetype == "folo-timeline" and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:find("saved", 1, true)
end, "starred not shown")
eq(select(2, header()), { " Starred (*) " })
eq(#vim.api.nvim_tabpage_list_wins(0), 3) -- header + list + preview
-- Nav keys work from the preview too; the list replaces the panel, the preview stays.
vim.api.nvim_set_current_win(vim.fn.bufwinid(vim.fn.bufnr("folo://preview")))
press("T")
eq(vim.api.nvim_buf_get_name(0), "folo://timeline/all")
eq(#vim.api.nvim_tabpage_list_wins(0), 3)
press("D")
eq(#vim.api.nvim_tabpage_list_wins(0), 2)
eq(vim.t.folo_dashboard, true)
eq(vim.api.nvim_buf_get_name(0):match("Folo Dashboard$") ~= nil, true)
eq(#vim.api.nvim_list_tabpages(), tabs)

print("ok")
vim.cmd("qa!")
