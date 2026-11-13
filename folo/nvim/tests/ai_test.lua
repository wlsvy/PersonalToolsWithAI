-- Run: nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/ai_test.lua
local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local bin = vim.fn.tempname()
vim.fn.mkdir(bin, "p")
vim.uv.fs_symlink(dir .. "/fake_curl.sh", bin .. "/curl")
vim.env.PATH = bin .. ":" .. vim.env.PATH
vim.env.FAKE_FOLO_LOG = vim.fn.tempname()
vim.env.FAKE_CURL_LOG = vim.fn.tempname()
vim.env.FAKE_CLAUDE_LOG = vim.fn.tempname()
vim.fn.writefile({}, vim.env.FAKE_CLAUDE_LOG)

local summary_prompt, translation_prompt = vim.fn.tempname(), vim.fn.tempname()
vim.fn.writefile({ "SUMMARY PROMPT" }, summary_prompt)
vim.fn.writefile({ "TRANSLATE PROMPT" }, translation_prompt)
local out = vim.fn.tempname()

local folo = require("folo")
folo.setup({
  cmd = { dir .. "/fake_folo.sh" },
  render = "strip",
  timeout_ms = 2000,
  preview_debounce_ms = 10,
  lazy_load_margin = 0,
  article = { thin_chars = 20 },
  ai = {
    cmd = { dir .. "/fake_claude.sh" },
    config_dir = "/tmp/fake-profile",
    prompts = { summary = summary_prompt, translation = translation_prompt },
    concurrency = 2,
    timeout_ms = { summary = 3000, translation = 3000 },
    confirm_over = 3,
    dir = out,
  },
})
local ai = require("folo.ai")
local cli = require("folo.cli")

local function eq(got, want)
  assert(vim.deep_equal(got, want), vim.inspect(got) .. " ~= " .. vim.inspect(want))
end
local function wait(fn, what)
  assert(vim.wait(8000, fn, 10), type(what) == "function" and what() or what)
end
local function claude_log()
  return vim.fn.readfile(vim.env.FAKE_CLAUDE_LOG)
end
local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

local notices = {}
vim.notify = function(msg)
  table.insert(notices, msg)
end
local answer = 1
vim.fn.confirm = function()
  return answer
end

local function entry(id, url)
  return { id = id, title = "T" .. id, url = url or ("https://x/" .. id), feed = "F", published = "2026-01-01", read = true }
end
-- Ids 1 and 2 exist in fake_folo.sh; others use the fake's fixed fallback below.
local entries = { entry("1"), entry("2"), entry("d2", "https://x/denied") }
local original_timeline = cli.timeline
cli.timeline = function(_, cb)
  cb(nil, { entries = entries })
end
local original_entry = cli.entry
cli.entry = function(id, cb)
  if id == "d2" then
    return cb(nil, { content = "<a>Comments</a>" })
  end
  if id:sub(1, 1) == "n" then
    return cb(nil, { content = "<p>" .. id .. " long enough article body text here</p>" })
  end
  original_entry(id, cb)
end

vim.cmd("source " .. dir .. "/../plugin/folo.lua")
require("folo.ui").timeline({}, "all")
local list = vim.api.nvim_get_current_buf()
local function lines()
  return vim.api.nvim_buf_get_lines(list, 0, -1, false)
end
local function preview_text()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b) == "folo://preview" then
      return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
    end
  end
  return ""
end
wait(function()
  return #lines() == 3 and lines()[1]:find("T1", 1, true)
end, "list did not load")

-- No AI happens from opening or previewing.
vim.wait(300)
eq(claude_log(), {})

-- Summary of the current entry creates a child row under it; the cursor stays on the entry.
vim.api.nvim_win_set_cursor(0, { 1, 0 })
press("s")
assert(lines()[2]:find("└ summary ", 1, true), lines()[2])
eq(vim.api.nvim_win_get_cursor(0)[1], 1)
wait(function()
  return lines()[2] == "   └ summary"
end, function()
  return vim.inspect(lines())
end)
local stored = table.concat(ai.read("1"), "\n")
assert(stored:find("# T1", 1, true) and stored:find("SUMMARY of # T1", 1, true), stored)

-- The invocation matches the extension host: no tools, separate profile, temp cwd, no session.
local log = table.concat(claude_log(), "\n")
assert(log:find("--tools  --no-session-persistence", 1, true), log)
assert(log:find("-p --model sonnet --system-prompt SUMMARY PROMPT", 1, true), log)
assert(log:find("env /tmp/fake-profile", 1, true), log)
assert(not log:find("cwd " .. vim.fn.getcwd(), 1, true), log)

-- Pressing s again does nothing.
local before = #claude_log()
press("s")
vim.wait(300)
eq(#claude_log(), before)
assert(notices[#notices]:find("queued 0, skipped 1", 1, true), notices[#notices])

-- Cursor on the child previews the file; the parent shows the article again.
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
wait(function()
  return preview_text():find("SUMMARY of", 1, true) ~= nil
end, preview_text)

-- Translation appends below the summary; the live preview follows it.
press("t")
wait(function()
  return lines()[2] == "   └ summary + translation"
end, function()
  return vim.inspect(lines())
end)
stored = table.concat(ai.read("1"), "\n")
local s_at, t_at = stored:find("SUMMARY of", 1, true), stored:find("TRANSLATION of", 1, true)
assert(s_at and t_at and s_at < t_at, stored)
assert(stored:find("## 번역", 1, true), stored)
wait(function()
  return preview_text():find("TRANSLATION of", 1, true) ~= nil
end, preview_text)
assert(claude_log()[#claude_log()]:find("end translation", 1, true))
press("t")
vim.wait(300)
assert(notices[#notices]:find("queued 0", 1, true), notices[#notices])

-- Moving down with Tab skips child rows; Tab on a child selects its parent.
vim.api.nvim_win_set_cursor(0, { 1, 0 })
press("<Tab>")
eq(vim.api.nvim_win_get_cursor(0)[1], 3)
eq(lines()[1]:sub(1, 1), "+")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
press("<Tab>")
eq(lines()[1]:sub(1, 1), " ")

-- A link-only entry whose article cannot be fetched never reaches Claude.
before = #claude_log()
vim.api.nvim_win_set_cursor(0, { #lines(), 0 })
press("s")
wait(function()
  return lines()[#lines()]:find("failed: article could not be loaded", 1, true) ~= nil
end, function()
  return vim.inspect(lines())
end)
eq(#claude_log(), before)

-- Failure writes nothing, shows the reason with a login hint, and the key retries.
entries = { entry("1"), entry("2") }
press("r")
wait(function()
  return lines()[3] and lines()[3]:find("T2", 1, true)
end, function()
  return vim.inspect(lines())
end)
vim.env.FAKE_CLAUDE_MODE = "login"
vim.api.nvim_win_set_cursor(0, { 3, 0 })
press("t")
wait(function()
  return (lines()[4] or ""):find("failed: Not logged in", 1, true) ~= nil
end, function()
  return vim.inspect(lines())
end)
assert(lines()[4]:find("CLAUDE_CONFIG_DIR=/tmp/fake-profile claude", 1, true), lines()[4])
eq(ai.read("2"), nil)
eq(#vim.tbl_filter(function(l)
  return l:find("start translation # T2", 1, true) ~= nil
end, claude_log()), 0)

vim.env.FAKE_CLAUDE_MODE = "empty"
vim.api.nvim_win_set_cursor(0, { 3, 0 })
press("s")
wait(function()
  return (lines()[4] or ""):find("failed: empty response", 1, true) ~= nil
end, function()
  return vim.inspect(lines())
end)
eq(ai.read("2"), nil)

-- t on an entry with no summary runs summary first, then translation.
vim.env.FAKE_CLAUDE_MODE = ""
vim.api.nvim_win_set_cursor(0, { 3, 0 })
press("t")
wait(function()
  return lines()[4] == "   └ summary + translation"
end, function()
  return vim.inspect(lines())
end)
local order = table.concat(claude_log(), "\n")
local start_s = order:find("start summary # T2", 1, true)
local start_t = order:find("start translation # T2", 1, true)
assert(start_s and start_t and start_s < start_t, order)

-- x deletes after confirmation; declining keeps the file.
answer = 2
press("x")
assert(ai.read("2"))
answer = 1
press("x")
eq(ai.read("2"), nil)
eq(#lines(), 3)

-- Queue: selected entries run with bounded parallelism; the selection clears.
entries = { entry("n1"), entry("n2"), entry("n3") }
press("r")
wait(function()
  return lines()[3] and lines()[3]:find("Tn3", 1, true)
end, function()
  return vim.inspect(lines())
end)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
press("<Tab>")
press("<Tab>")
press("<Tab>")
local mark = #claude_log()
press("s")
eq(#vim.tbl_filter(function(l)
  return l:find("queued", 1, true) ~= nil
end, lines()) > 0, true)
eq(lines()[1]:sub(1, 1), " ")
wait(function()
  return ai.read("n1") and ai.read("n2") and ai.read("n3")
end, function()
  return vim.inspect(lines())
end)
local active, peak = 0, 0
for i = mark + 1, #claude_log() do
  local l = claude_log()[i]
  if l:sub(1, 6) == "start " then
    active = active + 1
    peak = math.max(peak, active)
  elseif l:sub(1, 4) == "end " then
    active = active - 1
  end
end
eq(peak, 2)

-- Over the limit asks first; declining queues nothing and keeps the selection.
local many = {}
for i = 1, 4 do
  table.insert(many, entry("m" .. i))
end
entries = many
press("r")
wait(function()
  return lines()[4] and lines()[4]:find("Tm4", 1, true)
end, function()
  return vim.inspect(lines())
end)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
for _ = 1, 4 do
  press("<Tab>")
end
answer = 2
press("s")
eq(lines()[1]:sub(1, 1), "+")
eq(#lines(), 4)

-- A summary on disk shows up for a list opened later (new session memory).
vim.fn.mkdir(out, "p")
vim.fn.writefile({ "# saved", "", "kept across restarts" }, ai.path("disk"))
entries = { entry("disk") }
vim.cmd("FoloCategory Fresh")
list = vim.api.nvim_get_current_buf()
wait(function()
  return lines()[2] == "   └ summary"
end, function()
  return vim.inspect(lines())
end)

-- Ids cannot escape the summary directory.
assert(vim.startswith(ai.path("../../evil"), out .. "/"))
assert(not ai.path("../../evil"):find("evil", 1, true))

-- The default prompts are the extension's and exist in this repository.
folo.config.ai.prompts = {}
folo.config.ai.dir = vim.fn.tempname()
local default_log_mark = #claude_log()
entries = { entry("n9") }
press("r")
wait(function()
  return (lines()[1] or ""):find("Tn9", 1, true)
end, function()
  return vim.inspect(lines())
end)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
press("s")
wait(function()
  return ai.read("n9")
end, function()
  return vim.inspect(lines())
end)
local default_log = table.concat(vim.list_slice(claude_log(), default_log_mark + 1), "\n")
assert(default_log:find("글의 내용을 한국어로 정리한다", 1, true), default_log)

cli.timeline, cli.entry = original_timeline, original_entry
print("ok")
