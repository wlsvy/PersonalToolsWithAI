local cli = require("folo.cli")
local render = require("folo.render")

local M = {}

-- Per-buffer view state, keyed by bufnr.
local state = {}

local function notify_err(err)
  vim.notify("folo: " .. err, vim.log.levels.ERROR)
end

-- bufnr() would treat a user-supplied category as a pattern and match it partially.
local function find_buf(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end
end

-- Open (or reuse) a scratch buffer named `name` in the current window.
local function scratch(name, filetype)
  local buf = find_buf(name)
  if not buf then
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
      vim.keymap.set("n", keys[name], fn, { buffer = buf, nowait = true, desc = "folo: " .. name })
    end
  end
end

local function close()
  vim.cmd("bdelete")
end

local function one_line(s)
  return (s:gsub("%s+", " "))
end

local function redraw(buf)
  local lines = {}
  for _, e in ipairs(state[buf].items) do
    local mark = e.read and " " or "*"
    table.insert(lines, ("%s %s  %s  %s"):format(mark, e.published:sub(1, 10), one_line(e.feed), one_line(e.title)))
  end
  set_lines(buf, #lines > 0 and lines or { "(no entries)" })
end

-- opts: {unread=, category=, collection=}; title names the buffer.
function M.timeline(opts, title)
  local cfg = require("folo").get_config()
  local buf = scratch("folo://timeline/" .. title, "folo-timeline")
  state[buf] = { items = {}, next = nil, loading = false }

  local function load_page(cursor)
    local s = state[buf]
    if s.loading then
      return
    end
    s.loading = true
    local function on_page(err, page)
      s.loading = false
      if err then
        return notify_err(err)
      end
      if state[buf] ~= s then
        return
      end
      vim.list_extend(s.items, page.entries)
      s.next = page.next
      redraw(buf)
    end
    if opts.collection then
      cli.collection({ cursor = cursor }, on_page)
    else
      cli.timeline({ unread = opts.unread, category = opts.category, cursor = cursor }, on_page)
    end
  end

  local function current()
    return state[buf].items[vim.api.nvim_win_get_cursor(0)[1]]
  end

  -- The list changes only after the CLI reports success.
  local function set_read(e, read)
    cli.set_read(e.id, read, function(err)
      if err then
        return notify_err(err)
      end
      e.read = read
      if vim.api.nvim_buf_is_valid(buf) and state[buf] then
        redraw(buf)
      end
    end)
  end

  map(buf, cfg.keymaps.timeline, {
    open = function()
      local e = current()
      if e then
        if not e.read then
          set_read(e, true)
        end
        M.entry(e.id)
      end
    end,
    toggle_read = function()
      local e = current()
      if e then
        set_read(e, not e.read)
      end
    end,
    open_url = function()
      local e = current()
      if e and e.url ~= "" then
        vim.ui.open(e.url)
      end
    end,
    next_page = function()
      local s = state[buf]
      if s.next then
        load_page(s.next)
      else
        vim.notify("folo: no more entries")
      end
    end,
    refresh = function()
      state[buf].items = {}
      state[buf].next = nil
      load_page(nil)
    end,
    close = close,
  })
  load_page(nil)
end

function M.category(name)
  M.timeline({ category = name }, "category/" .. name)
end

-- Lists the account's categories so names need not be remembered.
function M.pick_category()
  cli.categories(function(err, names)
    if err then
      return notify_err(err)
    end
    if #names == 0 then
      return vim.notify("folo: no categories")
    end
    vim.ui.select(names, { prompt = "Folo category" }, function(name)
      if name then
        M.category(name)
      end
    end)
  end)
end

function M.starred()
  M.timeline({ collection = true }, "starred")
end

local function show_entry(buf, e, body)
  local lines = { "# " .. one_line(e.title), "", e.url, e.feed .. "  " .. e.published, "" }
  set_lines(buf, vim.list_extend(lines, body))
end

function M.entry(id)
  local cfg = require("folo").get_config()
  cli.entry(id, function(err, e)
    if err then
      return notify_err(err)
    end
    render.to_lines(e.content or "", cfg.render, function(body)
      local buf = scratch("folo://entry/" .. id, "markdown")
      state[buf] = { items = {}, entry = e }
      show_entry(buf, e, body)
      map(buf, cfg.keymaps.entry, {
        -- Replaces a link-only feed body; on failure the current body stays.
        readability = function()
          cli.readability(id, function(read_err, content)
            if read_err then
              return notify_err(read_err)
            end
            if content == "" then
              return vim.notify("folo: no readable content")
            end
            render.to_lines(content, cfg.render, function(full)
              if vim.api.nvim_buf_is_valid(buf) then
                show_entry(buf, e, full)
              end
            end)
          end)
        end,
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

return M
