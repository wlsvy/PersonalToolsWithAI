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

local function sender(from)
  -- "Alice Kim <a@x>" -> "Alice Kim"; bare addresses stay as they are.
  local name = from:match('^%s*"?(.-)"?%s*<')
  return (name and name ~= "") and name or from
end

-- triage(cb(err, { total = n, messages = { { id, from, subject, date } } })); cb on the main loop.
function M.triage(cb)
  local cfg = require("folo").get_config()
  local g = cfg.gmail
  local cmd = vim.list_extend(vim.deepcopy(g.cmd), { "gmail", "+triage", "--format", "json", "--max", tostring(g.max) })
  if g.query then
    vim.list_extend(cmd, { "--query", g.query })
  end
  cmd = require("folo.cli").resolve(cmd)
  local ok, err = pcall(vim.system, cmd, { text = true, timeout = cfg.timeout_ms }, function(res)
    vim.schedule(function()
      local perr, data = parse(res)
      if perr then
        return cb(perr)
      end
      local messages = {}
      for _, m in ipairs(data.messages or {}) do
        table.insert(messages, {
          id = m.id,
          from = sender(m.from or ""),
          subject = m.subject or "",
          -- RFC 2822 "Tue, 17 Nov 2026 11:37:59 +0000" -> "17 Nov"
          date = (m.date or ""):match("%d+ %a+") or "",
        })
      end
      cb(nil, { total = data.resultSizeEstimate or #messages, messages = messages })
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb(("cannot run %s: install gws or set `gmail.cmd` in setup() (%s)"):format(g.cmd[1], err))
    end)
  end
end

return M
