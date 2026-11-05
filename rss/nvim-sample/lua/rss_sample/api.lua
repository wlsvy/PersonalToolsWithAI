-- API v1 client (contract: rss/docs/api.ai.md). Only this module knows paths.
local M = {}

-- Quote a value for a curl config file.
local function quote(s)
  return '"' .. (s:gsub("\\", "\\\\"):gsub('"', '\\"')) .. '"'
end

local function query(params)
  local parts = {}
  for k, v in pairs(params or {}) do
    if v ~= nil and v ~= false then
      table.insert(parts, k .. "=" .. vim.uri_encode(tostring(v == true and 1 or v)))
    end
  end
  table.sort(parts)
  return #parts > 0 and ("?" .. table.concat(parts, "&")) or ""
end

-- request(method, path, {query=, body=}, cb(err, data)); cb runs on the main loop.
function M.request(method, path, opts, cb)
  local cfg = require("rss_sample").get_config()
  if not cfg then
    return
  end
  opts = opts or {}
  -- Token and body go through stdin (curl --config -) so they never show in `ps`.
  local conf = { "header = " .. quote("Authorization: Bearer " .. cfg.token) }
  if opts.body then
    table.insert(conf, "header = " .. quote("Content-Type: application/json"))
    table.insert(conf, "data-binary = " .. quote(vim.json.encode(opts.body)))
  end
  local url = cfg.url:gsub("/$", "") .. cfg.api_base .. path .. query(opts.query)
  local cmd = { "curl", "-sS", "-X", method, "-w", "\n%{http_code}", "--config", "-", url }

  vim.system(cmd, { text = true, stdin = table.concat(conf, "\n") .. "\n" }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        return cb("curl: " .. vim.trim(res.stderr or ""))
      end
      local body, status = res.stdout:match("^(.*)\n(%d+)$")
      status = tonumber(status)
      local ok, data = pcall(vim.json.decode, body ~= "" and body or "null", { luanil = { object = true, array = true } })
      if not status or status >= 300 then
        local msg = ok and type(data) == "table" and data.error or body
        return cb(("HTTP %s: %s"):format(status or "?", msg))
      end
      cb(nil, ok and data or nil)
    end)
  end)
end

function M.feeds(cb)
  M.request("GET", "/feeds", nil, cb)
end

function M.add_feed(url, cb)
  M.request("POST", "/feeds", { body = { url = url } }, cb)
end

function M.delete_feed(id, cb)
  M.request("DELETE", "/feeds/" .. id, nil, cb)
end

function M.refresh_feed(id, cb)
  M.request("POST", "/feeds/" .. id .. "/refresh", nil, cb)
end

-- params: { feed=, unread=, starred=, limit=, before= }
function M.entries(params, cb)
  M.request("GET", "/entries", { query = params }, cb)
end

function M.entry(id, cb)
  M.request("GET", "/entries/" .. id, nil, cb)
end

-- fields: { read=bool?, starred=bool? }
function M.update_entry(id, fields, cb)
  M.request("PATCH", "/entries/" .. id, { body = fields }, cb)
end

function M.read_all(feed, cb)
  M.request("POST", "/entries/read-all", { query = { feed = feed } }, cb)
end

function M.unread(cb)
  M.request("GET", "/unread", nil, cb)
end

return M
