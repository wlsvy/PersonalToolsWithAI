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

-- npm installs CLIs on Windows as `name.cmd` shims, which spawn cannot find by bare name.
function M.resolve(cmd)
  if vim.fn.has("win32") == 1 and vim.fn.executable(cmd[1] .. ".cmd") == 1 then
    cmd[1] = vim.fn.exepath(cmd[1] .. ".cmd")
  end
  return cmd
end

-- run(args, cb(err, data)); cb runs on the main loop. The token never goes through argv.
function M.run(args, cb)
  local cfg = require("folo").get_config()
  local cmd = M.resolve(vim.list_extend(vim.deepcopy(cfg.cmd), { "--format", "json" }))
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
    site = feed.siteUrl or "",
    starred = item.collections ~= nil,
    starred_at = item.collections and item.collections.createdAt,
  }
end

local function add_flag(args, name, value)
  if value ~= nil then
    vim.list_extend(args, { name, tostring(value) })
  end
end

local function list_page(args, cb)
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

-- timeline({unread=, category=, feed=, cursor=}, cb(err, {entries=, next=}))
function M.timeline(opts, cb)
  local cfg = require("folo").get_config()
  local args = { "timeline" }
  add_flag(args, "--view", cfg.view)
  add_flag(args, "--limit", cfg.page_size)
  add_flag(args, "--category", opts.category)
  add_flag(args, "--feed", opts.feed)
  add_flag(args, "--cursor", opts.cursor)
  if opts.unread then
    table.insert(args, "--unread-only")
  end
  list_page(args, cb)
end

-- collection({cursor=}, cb(err, {entries=, next=}))
function M.collection(opts, cb)
  local cfg = require("folo").get_config()
  local args = { "collection", "list" }
  add_flag(args, "--limit", cfg.page_size)
  add_flag(args, "--cursor", opts.cursor)
  list_page(args, function(err, page)
    -- Items here are the collection itself, whether or not the CLI marks them.
    for _, e in ipairs(page and page.entries or {}) do
      e.starred = true
    end
    -- The server pages this list by star time, but the CLI's cursor is a publish time.
    if page and page.next then
      page.next = page.entries[#page.entries].starred_at or page.next
    end
    cb(err, page)
  end)
end

-- categories(cb(err, names)): sorted unique category names of the subscriptions.
function M.categories(cb)
  local cfg = require("folo").get_config()
  local args = { "subscription", "list" }
  add_flag(args, "--view", cfg.view)
  M.run(args, function(err, data)
    if err then
      return cb(err)
    end
    local seen = {}
    for _, sub in ipairs(data.subscriptions or {}) do
      if sub.category and sub.category ~= "" then
        seen[sub.category] = true
      end
    end
    local names = vim.tbl_keys(seen)
    table.sort(names)
    cb(nil, names)
  end)
end

local VIEWS = { articles = 0, social = 1, pictures = 2, videos = 3, audio = 4, notifications = 5 }

-- unread(cb(err, {total=, items=})): subscriptions with unread entries in the configured view.
-- items: { feed=, title=, category=, count= }; total counts only the kept items.
function M.unread(cb)
  local cfg = require("folo").get_config()
  local view = cfg.view and (VIEWS[cfg.view] or tonumber(cfg.view))
  M.run({ "unread", "list" }, function(err, data)
    if err then
      return cb(err)
    end
    local items, total = {}, 0
    for _, it in ipairs(data.items or {}) do
      if view == nil or it.view == view then
        local count = tonumber(it.unreadCount) or 0
        total = total + count
        table.insert(items, {
          feed = it.feedId or it.sourceId,
          title = it.title or "",
          category = it.category,
          count = count,
        })
      end
    end
    cb(nil, { total = total, items = items })
  end)
end

-- readability(id, cb(err, content)); content is "" when nothing could be extracted.
function M.readability(id, cb)
  M.run({ "entry", "read", id }, function(err, data)
    if err then
      return cb(err)
    end
    cb(nil, data and data.content or "")
  end)
end

-- entry(id, cb(err, entry))
function M.entry(id, cb)
  M.run({ "entry", "get", id }, function(err, data)
    if err then
      return cb(err)
    end
    if not data then
      return cb("entry not found: " .. id)
    end
    cb(nil, normalize(data))
  end)
end

-- set_starred(id, starred, cb(err))
function M.set_starred(id, starred, cb)
  M.run({ "collection", starred and "add" or "remove", id }, function(err)
    cb(err)
  end)
end

-- set_read(id, read, cb(err))
function M.set_read(id, read, cb)
  M.run({ "entry", read and "mark-read" or "mark-unread", id }, function(err)
    cb(err)
  end)
end

return M
