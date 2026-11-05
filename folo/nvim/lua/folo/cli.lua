-- folo CLI client. Only this module knows CLI arguments and the JSON output shape.
local M = {}

local function error_message(err)
  local code = type(err) == "table" and err.code or "UNKNOWN_ERROR"
  local message = type(err) == "table" and err.message or tostring(err)
  if code == "UNAUTHORIZED" then
    return ("%s: %s (run `folo login` in a terminal or set FOLO_TOKEN)"):format(code, message)
  end
  return ("%s: %s"):format(code, message)
end

-- The CLI writes the success envelope to stdout and the failure envelope to stderr.
local function parse(res)
  local text = (res.stdout and res.stdout ~= "") and res.stdout or (res.stderr or "")
  local ok, envelope = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  if ok and type(envelope) == "table" and envelope.ok ~= nil then
    if envelope.ok then
      return nil, envelope.data
    end
    return error_message(envelope.error)
  end
  if res.code == 124 then
    return "timed out"
  end
  if res.code ~= 0 then
    return ("exit %d: %s"):format(res.code, vim.trim(res.stderr or ""))
  end
  return "invalid JSON from CLI"
end

-- run(args, cb(err, data)); cb runs on the main loop. The token never goes through argv.
function M.run(args, cb)
  local cfg = require("folo").get_config()
  local cmd = vim.list_extend(vim.deepcopy(cfg.cmd), { "--format", "json" })
  vim.list_extend(cmd, args)
  local ok, err = pcall(vim.system, cmd, { text = true, timeout = cfg.timeout_ms }, function(res)
    vim.schedule(function()
      cb(parse(res))
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb(("cannot run %s: install folocli or set `cmd` in setup() (%s)"):format(cfg.cmd[1], err))
    end)
  end
end

local function normalize(item)
  local e = item.entries or {}
  local feed = item.feeds or {}
  return {
    id = e.id,
    title = e.title or "",
    url = e.url or "",
    author = e.author or "",
    published = e.publishedAt or "",
    content = e.content,
    read = item.read == true,
    feed = feed.title or "",
  }
end

-- timeline({unread=, cursor=}, cb(err, {entries=, next=}))
function M.timeline(opts, cb)
  local cfg = require("folo").get_config()
  local args = { "timeline" }
  local function flag(name, value)
    if value ~= nil then
      vim.list_extend(args, { name, tostring(value) })
    end
  end
  flag("--view", cfg.view)
  flag("--limit", cfg.page_size)
  flag("--cursor", opts.cursor)
  if opts.unread then
    table.insert(args, "--unread-only")
  end
  M.run(args, function(err, data)
    if err then
      return cb(err)
    end
    local entries = {}
    for _, item in ipairs(data.entries or {}) do
      table.insert(entries, normalize(item))
    end
    cb(nil, { entries = entries, next = data.hasNext and data.nextCursor or nil })
  end)
end

-- entry(id, cb(err, entry)); falls back to readability when the feed has no content.
function M.entry(id, cb)
  M.run({ "entry", "get", id }, function(err, data)
    if err then
      return cb(err)
    end
    if not data then
      return cb("entry not found: " .. id)
    end
    local e = normalize(data)
    if e.content and e.content ~= "" then
      return cb(nil, e)
    end
    M.run({ "entry", "read", id }, function(read_err, readable)
      if read_err then
        return cb(read_err)
      end
      e.content = readable and readable.content or ""
      cb(nil, e)
    end)
  end)
end

-- set_read(id, read, cb(err))
function M.set_read(id, read, cb)
  M.run({ "entry", read and "mark-read" or "mark-unread", id }, function(err)
    cb(err)
  end)
end

return M
