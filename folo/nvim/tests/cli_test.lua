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
eq({ page.entries[1].starred, page.entries[2].starred }, { false, true })
eq(last_args(), "--format json timeline --unread-only")
assert(not vim.fn.readfile(log)[1]:find("--token", 1, true))

err, page = await(function(cb)
  cli.timeline({ cursor = "2026-01-01" }, cb)
end)
eq({ err, #page.entries, page.next }, { nil, 2, nil })

local e
err, e = await(function(cb)
  cli.entry("1", cb)
end)
eq({ err, e.content }, { nil, "<p>body</p>" })

local content
err, content = await(function(cb)
  cli.readability("2", cb)
end)
eq({ err, content }, { nil, "<p>readable</p>" })

err, content = await(function(cb)
  cli.readability("3", cb)
end)
eq({ err, content }, { nil, "" })

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

print("ok")
