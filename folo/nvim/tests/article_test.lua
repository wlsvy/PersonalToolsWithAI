-- Run: nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/article_test.lua
local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local bin = vim.fn.tempname()
vim.fn.mkdir(bin, "p")
vim.uv.fs_symlink(dir .. "/fake_curl.sh", bin .. "/curl")
vim.env.PATH = bin .. ":" .. vim.env.PATH
vim.env.FAKE_FOLO_LOG = vim.fn.tempname()
vim.env.FAKE_CURL_LOG = vim.fn.tempname()
vim.env.FAKE_BROWSER_LOG = vim.fn.tempname()

local folo = require("folo")
local article = require("folo.article")
folo.setup({
  cmd = { dir .. "/fake_folo.sh" },
  render = "strip",
  timeout_ms = 2000,
  list_width = 30,
  preview_debounce_ms = 10,
  lazy_load_margin = 0,
  open_confirm_over = 2,
  article = { browser_cmd = { dir .. "/fake_browser.sh" }, thin_chars = 20 },
  ai = { dir = vim.fn.tempname() },
})

local function eq(got, want)
  assert(vim.deep_equal(got, want), vim.inspect(got) .. " ~= " .. vim.inspect(want))
end

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

-- URL safety
for _, url in ipairs({
  "file:///etc/passwd", "javascript:alert(1)", "ftp://x/y", "http://localhost:8080/", "http://LOCALHOST/",
  "http://127.0.0.1/", "http://10.1.2.3/", "http://172.16.0.1/", "http://192.168.0.1/", "http://169.254.169.254/",
  "http://100.64.0.1/", "http://[::1]/", "http://printer.local/", "http://user@localhost/", "http://2130706433/",
  "http://0x7f000001/", "http://localhost./",
}) do
  assert(not article.safe_url(url), "should reject " .. url)
end
for _, url in ipairs({ "https://example.com/a?b=1", "http://172.32.0.1/", "https://user@example.com:8443/x", "HTTPS://Example.com/" }) do
  assert(article.safe_url(url), "should accept " .. url)
end
assert(not article.safe_url(nil))

-- Extraction
eq(article.extract("<BODY><NAV>menu</NAV><p>text</p><SCRIPT>x</SCRIPT></BODY>"), "<p>text</p>")
eq(article.extract("<body><article>short</article><article>the longer one</article></body>"), "the longer one")
eq(article.extract("<body><main>m</main>b</body>"), "m")
eq(article.extract("<p>no structure</p><script>unclosed"), "<p>no structure</p>")
local euc = vim.iconv("<body>한글</body>", "utf-8", "euc-kr")
eq(article.extract(euc, "text/html; charset=EUC-KR"), "한글")
eq(article.extract('<meta charset="euc-kr">' .. euc), "한글")
eq(article.text_len("<p>한글 ab</p>"), 5)

-- curl paths
local err, html = await(function(cb)
  article.fetch("https://x/page", cb)
end)
eq({ err, html }, { nil, "<p>Curl article text</p>" })
err = await(function(cb)
  article.fetch("https://x/denied", cb)
end)
eq(err, "HTTP 403")
err = await(function(cb)
  article.fetch("https://x/pdf", cb)
end)
eq(err, "not an HTML page (application/pdf)")
err = await(function(cb)
  article.fetch("https://x/down", cb)
end)
assert(err:find("could not resolve", 1, true), err)
err = await(function(cb)
  article.fetch("http://127.0.0.1/secret", cb)
end)
assert(err:find("private", 1, true), err)
assert(not table.concat(vim.fn.readfile(vim.env.FAKE_CURL_LOG), "\n"):find("127.0.0.1", 1, true))
assert(vim.fn.readfile(vim.env.FAKE_CURL_LOG)[1]:find("--proto-redir =http,https", 1, true))

-- Browser paths
err, html = await(function(cb)
  article.render_browser("https://x/page", cb)
end)
eq({ err, html }, { nil, "<p>Rendered by browser</p>" })
local browser_args = vim.fn.readfile(vim.env.FAKE_BROWSER_LOG)[1]
local profile = browser_args:match("--user%-data%-dir=(%S+)")
assert(profile and vim.fn.isdirectory(profile) == 0, "profile should be temporary and removed")
assert(browser_args:find("--headless=new", 1, true))
err = await(function(cb)
  article.render_browser("https://x/fail", cb)
end)
assert(err:find("crashed", 1, true), err)
err = await(function(cb)
  article.render_browser("http://10.0.0.1/", cb)
end)
assert(err:find("private", 1, true), err)

-- UI ---------------------------------------------------------------------
vim.cmd("source " .. dir .. "/../plugin/folo.lua")

local opened = {}
vim.ui.open = function(url)
  table.insert(opened, url)
  return {}, nil
end
local notices = {}
vim.notify = function(msg)
  table.insert(notices, msg)
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end
local function wait(fn, what)
  assert(vim.wait(4000, fn, 10), what)
end
local function buf_named(name)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b) == name then
      return b
    end
  end
end
local function preview_text()
  local b = buf_named("folo://preview")
  return b and table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n") or ""
end
local function wait_preview(text)
  local found = vim.wait(4000, function()
    return preview_text():find(text, 1, true) ~= nil
  end, 10)
  assert(found, "preview never showed " .. text .. ":\n" .. preview_text())
end
local function move_to(row)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
end

vim.cmd("Folo")
local list = vim.api.nvim_get_current_buf()
local list_win = vim.api.nvim_get_current_win()
eq(vim.api.nvim_buf_get_name(list), "folo://timeline/all")
eq(#vim.api.nvim_tabpage_list_wins(0), 2)
local layout = vim.fn.winlayout()
eq(layout[1], "row")
eq(vim.api.nvim_win_get_width(list_win), 30)
local function lines()
  return vim.api.nvim_buf_get_lines(list, 0, -1, false)
end
wait(function()
  return lines()[1]:find("first line", 1, true) ~= nil
end, "list did not load")
eq(lines()[1], " *    📰 2026-01-02  F1  first line")
eq(vim.api.nvim_get_current_win(), list_win)

-- First entry's feed body is thin ("body"), Folo readable is thin, so curl appends after it.
wait_preview("Generic page")
assert(preview_text():find("body", 1, true), "feed body must stay")
assert(preview_text():find("## Article (curl)", 1, true), preview_text())
assert(not vim.fn.readfile(vim.env.FAKE_FOLO_LOG)[1]:find("mark-read"), "preview must not mark read")
eq(lines()[1]:sub(2, 2), "*")

-- Moving previews another entry without marking anything read.
-- This entry has no URL, so curl is never attempted and the preview says why.
move_to(2)
wait_preview("# second")
wait_preview("Could not load article: only http and https")
eq(lines()[1]:sub(2, 2), "*")

-- Cached preview issues no new CLI call.
local calls = #vim.fn.readfile(vim.env.FAKE_FOLO_LOG)
move_to(1)
wait_preview("# first")
vim.wait(100)
eq(#vim.fn.readfile(vim.env.FAKE_FOLO_LOG), calls)

-- Selection: toggle moves down, marks persist, paging keeps them, unsafe URLs are skipped.
vim.api.nvim_win_set_cursor(0, { 1, 0 })
press("<Tab>")
eq(lines()[1]:sub(1, 1), "+")
eq(vim.api.nvim_win_get_cursor(0)[1], 2)
press("<Tab>")
eq(lines()[2]:sub(1, 1), "+")
eq(vim.api.nvim_win_get_cursor(0)[1], 2)
press("]p")
wait(function()
  return lines()[3] ~= nil
end, "next page did not load")
-- The next page repeats entry 2 at the cursor time; it is shown once.
eq(#lines(), 3)
eq(lines()[1]:sub(1, 1), "+")
vim.api.nvim_win_set_cursor(0, { 3, 0 })
press("<Tab>")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
press("<Tab>")
eq(lines()[2]:sub(1, 1), " ")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
press("<Tab>")
press("gx")
eq(opened, { "https://x/1" })
assert(notices[#notices]:find("skipped 2", 1, true), vim.inspect(notices))
eq(lines()[1]:sub(1, 1), " ")

-- gx without a selection opens the current entry; a non-web URL is never opened.
opened = {}
vim.api.nvim_win_set_cursor(0, { 3, 0 })
press("gx")
eq(opened, {})
vim.api.nvim_win_set_cursor(0, { 1, 0 })
press("gx")
eq(opened, { "https://x/1" })

-- Enter marks read and focuses the preview; preview q returns to the list.
move_to(1)
vim.wait(50)
press("<CR>")
eq(vim.api.nvim_get_current_buf(), buf_named("folo://preview"))
wait(function()
  return lines()[1]:sub(2, 2) == " "
end, "entry was not marked read")

-- R renders in the browser, from the preview window.
press("R")
wait_preview("## Article (browser)")
wait_preview("Rendered by browser")
press("q")
eq(vim.api.nvim_get_current_win(), list_win)

-- A failed refresh notifies; the next refresh recovers.
local count = #notices
vim.env.FAKE_FOLO_MODE = "crash"
press("r")
vim.wait(200)
assert(#notices > count, "refresh failure should notify")
vim.env.FAKE_FOLO_MODE = ""
press("r")
wait(function()
  return lines()[1] and lines()[1]:find("first line", 1, true) ~= nil
end, "refresh did not reload")

-- Running a command from the preview keeps the preview window.
vim.api.nvim_set_current_win(vim.fn.bufwinid(buf_named("folo://preview")))
vim.cmd("FoloStarred")
eq(vim.api.nvim_buf_get_name(0), "folo://timeline/starred")
eq(#vim.api.nvim_tabpage_list_wins(0), 2)
wait_preview("# saved")

-- Picker and prefix names.
local offered
vim.ui.select = function(items, _, on_choice)
  offered = items
  on_choice("News")
end
vim.cmd("FoloCategory")
wait(function()
  return vim.api.nvim_buf_get_name(0) == "folo://timeline/category/News"
end, "picked category did not open")
eq(offered, { "AI", "News" })
wait_preview("# news item")
vim.cmd("FoloCategory New")
eq(vim.api.nvim_buf_get_name(0), "folo://timeline/category/New")
assert(buf_named("folo://timeline/category/News"))

-- Folo readability preferred over curl when it is long enough.
local ui_cli = require("folo.cli")
local original = ui_cli.timeline
ui_cli.timeline = function(_, cb)
  cb(nil, { entries = { { id = "8", title = "folo readable", url = "https://x/8", feed = "F", published = "", read = true } } })
end
local curl_calls = #vim.fn.readfile(vim.env.FAKE_CURL_LOG)
vim.cmd("FoloCategory Readable")
wait_preview("## Article (Folo)")
wait_preview("LONGFOLO")
eq(#vim.fn.readfile(vim.env.FAKE_CURL_LOG), curl_calls)
ui_cli.timeline = original

-- auto_fetch off: no curl, failure message offers R.
folo.config.article.auto_fetch = false
ui_cli.timeline = function(_, cb)
  cb(nil, { entries = { { id = "2", title = "fresh", url = "https://x/fresh", feed = "F", published = "", read = true } } })
end
vim.cmd("FoloCategory NoAuto")
wait_preview("Could not load article")
ui_cli.timeline = original
folo.config.article.auto_fetch = true

-- ? toggles a help popup that never takes focus and follows the live keymaps.
local function help_text()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n"), win
    end
  end
end
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local help_list_win = vim.api.nvim_get_current_win()
eq(help_text(), nil)
folo.config.keymaps.list.refresh = "gR"
folo.config.keymaps.list.toggle_read = false
press("?")
local text, float = help_text()
assert(text:find("<Tab>", 1, true) and text:find("gR", 1, true), text)
assert(not text:find("Toggle read", 1, true), text)
assert(text:find("+ selected", 1, true), text)
eq(vim.api.nvim_get_current_win(), help_list_win)
eq(vim.api.nvim_win_get_config(float).focusable, false)
folo.config.keymaps.list.refresh = "r"
folo.config.keymaps.list.toggle_read = "m"
press("?")
eq(help_text(), nil)

-- Moving to the preview closes it; ? there shows the preview's keys; q closes it again.
press("?")
press("<CR>")
eq(help_text(), nil)
press("?")
text = help_text()
assert(text:find("headless browser", 1, true) and not text:find("<Tab>", 1, true), text)
press("q")
eq(help_text(), nil)
eq(vim.api.nvim_get_current_win(), help_list_win)

-- Opening more pages than the limit asks first; declining keeps the selection.
ui_cli.timeline = function(_, cb)
  local entries = {}
  for i = 1, 3 do
    table.insert(entries, { id = "c" .. i, title = "t" .. i, url = "https://x/c" .. i, feed = "F", published = "", read = true })
  end
  cb(nil, { entries = entries })
end
vim.cmd("FoloCategory Many")
ui_cli.timeline = original
local many = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 1, 0 })
press("<Tab>")
press("<Tab>")
press("<Tab>")
local answer = 2
vim.fn.confirm = function()
  return answer
end
opened = {}
press("gx")
eq(opened, {})
eq(vim.api.nvim_buf_get_lines(many, 0, 1, false)[1]:sub(1, 1), "+")
answer = 1
press("gx")
eq(opened, { "https://x/c1", "https://x/c2", "https://x/c3" })
eq(vim.api.nvim_buf_get_lines(many, 0, 1, false)[1]:sub(1, 1), " ")

-- List q closes both windows' view and an open help popup.
press("?")
eq(#vim.api.nvim_tabpage_list_wins(0), 3)
press("q")
eq(#vim.api.nvim_tabpage_list_wins(0), 1)

print("ok")
