-- gws CLI client for the dashboard's Mail section. Only this module knows gws argv and output.
local M = {}

-- gws prints `{ "error": {...} }` to stdout and a log line ("Using keyring backend") to stderr.
local function parse(res)
  local ok, data = pcall(vim.json.decode, res.stdout or "", { luanil = { object = true, array = true } })
  if ok and type(data) == "table" then
    if data.error then
      local msg = data.error.message or vim.inspect(data.error)
      if data.error.reason == "authError" then
        msg = msg:match("^[^.]*") .. " (run `gws auth login` in a terminal)"
      end
      return msg
    end
    if res.code == 0 then
      return nil, data
    end
  end
  if res.code == 124 then
    return "timed out"
  end
  if res.code ~= 0 then
    return ("exit %d: %s"):format(res.code, vim.trim(res.stderr or ""))
  end
  return "invalid JSON from gws"
end

-- run(args, cb(err, data)); cb runs on the main loop.
local function run(args, cb)
  local cfg = require("folo").get_config()
  local cmd = require("folo.cli").resolve(vim.list_extend(vim.deepcopy(cfg.gmail.cmd), args))
  local ok, err = pcall(vim.system, cmd, { text = true, timeout = cfg.timeout_ms }, function(res)
    vim.schedule(function()
      cb(parse(res))
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb(("cannot run %s: install gws or set `gmail.cmd` in setup() (%s)"):format(cfg.gmail.cmd[1], err))
    end)
  end
end

local function sender(from)
  -- "Alice Kim <a@x>" -> "Alice Kim"; bare addresses stay as they are.
  local name = from:match('^%s*"?(.-)"?%s*<')
  return (name and name ~= "") and name or from
end

-- RFC 2822 "Tue, 17 Nov 2026 11:37:59 +0000" -> "17 Nov"
local function short_date(date)
  return (date or ""):match("%d+ %a+") or ""
end

-- triage(cb(err, { total = n, messages = { { id, from, subject, date } } })); cb on the main loop.
function M.triage(cb)
  local g = require("folo").get_config().gmail
  local args = { "gmail", "+triage", "--format", "json", "--max", tostring(g.max) }
  if g.query then
    vim.list_extend(args, { "--query", g.query })
  end
  run(args, function(err, data)
    if err then
      return cb(err)
    end
    local messages = {}
    for _, m in ipairs(data.messages or {}) do
      table.insert(messages, { id = m.id, from = sender(m.from or ""), subject = m.subject or "", date = short_date(m.date) })
    end
    cb(nil, { total = data.resultSizeEstimate or #messages, messages = messages })
  end)
end

local function header(part, name)
  for _, h in ipairs(part.headers or {}) do
    if h.name:lower() == name then
      return h.value
    end
  end
end

-- Gmail returns each part's bytes base64url-encoded in the part's own charset.
local function decode(part)
  local s = part.body.data:gsub("-", "+"):gsub("_", "/")
  local ok, bytes = pcall(vim.base64.decode, s .. ("="):rep((4 - #s % 4) % 4))
  if not ok then
    return ""
  end
  local charset = ((header(part, "content-type") or ""):match('charset="?([%w_.:-]+)') or "utf-8"):lower()
  if charset ~= "utf-8" and charset ~= "us-ascii" then
    local converted = vim.iconv(bytes, charset, "utf-8")
    if converted and converted ~= "" then
      bytes = converted
    end
  end
  return (bytes:gsub("\r\n", "\n"))
end

-- Depth-first: the first text/plain wins over the first text/html; named parts are attachments.
local function walk(part, found)
  if part.filename and part.filename ~= "" then
    table.insert(found.attachments, part.filename)
  elseif part.body and part.body.data then
    if part.mimeType == "text/plain" and not found.plain then
      found.plain = part
    elseif part.mimeType == "text/html" and not found.html then
      found.html = part
    end
  end
  for _, p in ipairs(part.parts or {}) do
    walk(p, found)
  end
end

-- message(id, cb(err, { subject, from, date, text = lines, attachments = names })); cb on the main loop.
function M.message(id, cb)
  local params = vim.json.encode({ userId = "me", id = id, format = "full" })
  run({ "gmail", "users", "messages", "get", "--params", params }, function(err, data)
    if err then
      return cb(err)
    end
    local payload = data.payload or {}
    local found = { attachments = {} }
    walk(payload, found)
    local msg = {
      subject = header(payload, "subject") or "",
      from = header(payload, "from") or "",
      date = short_date(header(payload, "date")),
      attachments = found.attachments,
    }
    if found.plain then
      msg.text = vim.split(vim.trim(decode(found.plain)), "\n", { plain = true })
      return cb(nil, msg)
    end
    if not found.html then
      msg.text = { "(no text body)" }
      return cb(nil, msg)
    end
    require("folo.render").to_lines(decode(found.html), require("folo").get_config().render, function(lines)
      msg.text = lines
      cb(nil, msg)
    end)
  end)
end

return M
