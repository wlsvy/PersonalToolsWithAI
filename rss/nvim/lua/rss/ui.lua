local api = require("rss.api")
local render = require("rss.render")

local M = {}

-- Per-buffer view state, keyed by bufnr.
local state = {}

local function notify_err(err)
  vim.notify("rss: " .. err, vim.log.levels.ERROR)
end

-- Open (or reuse) a scratch buffer named `name` in the current window.
local function scratch(name, filetype)
  local buf = vim.fn.bufnr(name)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buf, name)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      callback = function()
        state[buf] = nil
      end,
    })
  end
  vim.bo[buf].filetype = filetype
  vim.api.nvim_set_current_buf(buf)
  return buf
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function map(buf, keys, actions)
  for name, fn in pairs(actions) do
    if keys[name] then
      vim.keymap.set("n", keys[name], fn, { buffer = buf, nowait = true, desc = "rss: " .. name })
    end
  end
end

local function current_item(buf)
  local s = state[buf]
  return s and s.items[vim.api.nvim_win_get_cursor(0)[1]]
end

local function close()
  vim.cmd("bdelete")
end

-- Feeds -----------------------------------------------------------------

local function feed_line(f)
  local title = f.title ~= "" and f.title or f.url
  local cat = f.category ~= "" and ("  [" .. f.category .. "]") or ""
  local err = f.error ~= "" and "  !" or ""
  return ("%5d  %s%s%s"):format(f.unread, title, cat, err)
end

function M.feeds()
  local cfg = require("rss").get_config()
  if not cfg then
    return
  end
  local buf = scratch("rss://feeds", "rss-feeds")
  local function load()
    api.feeds(function(err, feeds)
      if err then
        return notify_err(err)
      end
      state[buf] = { items = feeds }
      set_lines(buf, vim.tbl_map(feed_line, feeds))
    end)
  end
  map(buf, cfg.keymaps.feeds, {
    open = function()
      local f = current_item(buf)
      if f then
        M.entries({ feed = f.id }, f.title ~= "" and f.title or f.url)
      end
    end,
    refresh = function()
      local f = current_item(buf)
      if f then
        api.refresh_feed(f.id, function(err)
          if err then
            return notify_err(err)
          end
          load()
        end)
      end
    end,
    delete = function()
      local f = current_item(buf)
      if f and vim.fn.confirm("Delete feed " .. (f.title ~= "" and f.title or f.url) .. "?", "&Yes\n&No", 2) == 1 then
        api.delete_feed(f.id, function(err)
          if err then
            return notify_err(err)
          end
          load()
        end)
      end
    end,
    close = close,
  })
  load()
end

-- Entries ---------------------------------------------------------------

local function entry_line(e)
  return ("%s%s %s  %s"):format(
    e.read and " " or "●",
    e.starred and "★" or " ",
    os.date("%Y-%m-%d", e.published),
    e.title ~= "" and e.title or e.url
  )
end

local function redraw_entries(buf)
  set_lines(buf, vim.tbl_map(entry_line, state[buf].items))
end

-- params: API query for /entries (feed, unread, starred); title names the buffer.
function M.entries(params, title)
  local cfg = require("rss").get_config()
  if not cfg then
    return
  end
  local buf = scratch("rss://entries/" .. title, "rss-entries")
  state[buf] = { items = {}, next = nil, params = params }

  local function load_page(before)
    local q = vim.tbl_extend("force", params, { limit = cfg.page_size, before = before })
    api.entries(q, function(err, page)
      if err then
        return notify_err(err)
      end
      local s = state[buf]
      vim.list_extend(s.items, page.entries)
      s.next = page.next
      redraw_entries(buf)
    end)
  end

  local function update(e, fields)
    api.update_entry(e.id, fields, function(err)
      if err then
        return notify_err(err)
      end
      e.read = fields.read == nil and e.read or fields.read
      e.starred = fields.starred == nil and e.starred or fields.starred
      if vim.api.nvim_buf_is_valid(buf) then
        redraw_entries(buf)
      end
    end)
  end

  map(buf, cfg.keymaps.entries, {
    open = function()
      local e = current_item(buf)
      if e then
        if not e.read then
          update(e, { read = true })
        end
        M.entry(e.id)
      end
    end,
    toggle_read = function()
      local e = current_item(buf)
      if e then
        update(e, { read = not e.read })
      end
    end,
    toggle_star = function()
      local e = current_item(buf)
      if e then
        update(e, { starred = not e.starred })
      end
    end,
    open_url = function()
      local e = current_item(buf)
      if e and e.url ~= "" then
        vim.ui.open(e.url)
      end
    end,
    next_page = function()
      local s = state[buf]
      if s.next then
        load_page(s.next)
      else
        vim.notify("rss: no more entries")
      end
    end,
    close = close,
  })
  load_page(nil)
end

-- Entry -----------------------------------------------------------------

function M.entry(id)
  local cfg = require("rss").get_config()
  if not cfg then
    return
  end
  api.entry(id, function(err, e)
    if err then
      return notify_err(err)
    end
    render.to_lines(e.content or "", cfg.render, function(body)
      local buf = scratch("rss://entry/" .. id, "markdown")
      state[buf] = { items = {}, entry = e }
      local lines = { "# " .. e.title, "", e.url, os.date("%Y-%m-%d %H:%M", e.published), "" }
      set_lines(buf, vim.list_extend(lines, body))
      map(buf, cfg.keymaps.entry, {
        open_url = function()
          if e.url ~= "" then
            vim.ui.open(e.url)
          end
        end,
        close = close,
      })
    end)
  end)
end

-- Commands --------------------------------------------------------------

function M.add(url)
  api.add_feed(url, function(err, f)
    if err then
      return notify_err(err)
    end
    vim.notify(("rss: added %s (%d entries)%s"):format(f.title ~= "" and f.title or f.url, f.unread,
      f.error ~= "" and (", fetch error: " .. f.error) or ""))
  end)
end

-- refresh(feed_id?): one feed, or every feed when nil.
function M.refresh(feed_id)
  local function done(err)
    if err then
      return notify_err(err)
    end
    vim.notify("rss: refreshed")
  end
  if feed_id then
    return api.refresh_feed(feed_id, done)
  end
  api.feeds(function(err, feeds)
    if err then
      return notify_err(err)
    end
    local pending = #feeds
    if pending == 0 then
      return done()
    end
    for _, f in ipairs(feeds) do
      api.refresh_feed(f.id, function(e)
        if e then
          notify_err(e)
        end
        pending = pending - 1
        if pending == 0 then
          done()
        end
      end)
    end
  end)
end

return M
