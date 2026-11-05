local article = require("folo.article")
local cli = require("folo.cli")
local render = require("folo.render")

local M = {}

local PREVIEW_NAME = "folo://preview"

-- Per-list state, keyed by bufnr.
local state = {}
-- Finished previews by entry id, kept for the session.
local cache = {}
-- The list driving the preview, and a counter that makes older async results stale.
local preview = { list = nil, entry = nil, generation = 0 }

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

local function create_scratch(name, filetype)
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

local function one_line(s)
  return (s:gsub("%s+", " "))
end

-- Preview ---------------------------------------------------------------

local function preview_buf()
  return create_scratch(PREVIEW_NAME, "markdown")
end

local function preview_win()
  local buf = find_buf(PREVIEW_NAME)
  if not buf then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
end

local function list_width(cfg)
  if cfg.list_width >= 1 then
    return math.floor(cfg.list_width)
  end
  return math.max(20, math.floor(vim.o.columns * cfg.list_width))
end

-- Shows the preview beside the current window; focus stays on the current window.
local function ensure_preview_win(cfg)
  local win = preview_win()
  if not win then
    local list_win = vim.api.nvim_get_current_win()
    vim.cmd("rightbelow vsplit")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, preview_buf())
    vim.api.nvim_set_current_win(list_win)
  end
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.api.nvim_win_set_width(vim.api.nvim_get_current_win(), list_width(cfg))
  return win
end

local function header(e)
  return { "# " .. one_line(e.title), "", e.url, one_line(e.feed) .. "  " .. e.published, "" }
end

-- view = {entry=, body=lines, article=lines|nil, source=, status=}
local function draw_preview(view)
  local lines = header(view.entry)
  vim.list_extend(lines, view.body or {})
  if view.article then
    vim.list_extend(lines, { "", "---", "", ("## Article (%s)"):format(view.source), "" })
    vim.list_extend(lines, view.article)
  end
  if view.status then
    vim.list_extend(lines, { "", "> " .. view.status })
  end
  local buf = preview_buf()
  set_lines(buf, lines)
  local win = preview_win()
  if win then
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
  end
end

local function is_current(generation)
  return preview.generation == generation
end

local function show_article(view, generation, html, source, finish)
  render.to_lines(html, require("folo").get_config().render, function(lines)
    if not is_current(generation) then
      return
    end
    view.article, view.source, view.status = lines, source, nil
    finish()
  end)
end

local function article_failed(view, reason)
  view.status = ("Could not load article: %s. Press R to render in a browser."):format(reason)
end

local function fetch_with_curl(view, generation, finish)
  article.fetch(view.entry.url, function(err, html)
    if not is_current(generation) then
      return
    end
    if err then
      article_failed(view, err)
      return finish()
    end
    show_article(view, generation, html, "curl", finish)
  end)
end

-- Feed body is kept; thin bodies get the article appended below it.
local function fetch_article(view, generation, finish)
  local cfg = require("folo").get_config().article
  cli.readability(view.entry.id, function(err, content)
    if not is_current(generation) then
      return
    end
    if not err and article.text_len(content) >= cfg.thin_chars then
      return show_article(view, generation, content, "Folo", finish)
    end
    if cfg.auto_fetch then
      view.status = "Loading article…"
      draw_preview(view)
      return fetch_with_curl(view, generation, finish)
    end
    article_failed(view, err or "no readable content")
    finish()
  end)
end

local function show_preview(e)
  preview.generation = preview.generation + 1
  preview.entry = e
  local generation = preview.generation
  if cache[e.id] then
    return draw_preview(cache[e.id])
  end
  local view = { entry = e, status = "Loading…" }
  draw_preview(view)
  local cfg = require("folo").get_config()
  cli.entry(e.id, function(err, full)
    if not is_current(generation) then
      return
    end
    if err then
      view.status = err
      return draw_preview(view)
    end
    local html = full.content or ""
    render.to_lines(html, cfg.render, function(body)
      if not is_current(generation) then
        return
      end
      view.body, view.status = body, nil
      local function finish()
        cache[e.id] = view
        draw_preview(view)
      end
      if article.text_len(html) >= cfg.article.thin_chars then
        return finish()
      end
      view.status = "Loading article…"
      draw_preview(view)
      fetch_article(view, generation, finish)
    end)
  end)
end

local function render_in_browser()
  local e = preview.entry
  if not e then
    return
  end
  preview.generation = preview.generation + 1
  local generation = preview.generation
  local view = cache[e.id] or { entry = e }
  view.status = "Rendering in a headless browser…"
  draw_preview(view)
  article.render_browser(e.url, function(err, html)
    if not is_current(generation) then
      return
    end
    if err then
      view.status = "Browser render failed: " .. err
      return draw_preview(view)
    end
    show_article(view, generation, html, "browser", function()
      cache[e.id] = view
      draw_preview(view)
    end)
  end)
end

local function open_urls(entries)
  local cfg = require("folo").get_config()
  local urls, skipped = {}, 0
  for _, e in ipairs(entries) do
    -- Feed-supplied URLs reach the OS opener, which would also launch other schemes.
    if e.url:match("^[hH][tT][tT][pP][sS]?://") then
      table.insert(urls, e.url)
    else
      skipped = skipped + 1
    end
  end
  if #urls > cfg.open_confirm_over then
    if vim.fn.confirm(("Open %d pages?"):format(#urls), "&Yes\n&No", 2) ~= 1 then
      return false
    end
  end
  local failed = 0
  for _, url in ipairs(urls) do
    local _, err = vim.ui.open(url)
    if err then
      failed = failed + 1
      notify_err(err)
    end
  end
  if skipped > 0 then
    vim.notify(("folo: skipped %d entries without a web URL"):format(skipped))
  end
  return failed == 0 and #urls > 0
end

-- List ------------------------------------------------------------------

local function redraw(buf)
  local lines = {}
  for _, e in ipairs(state[buf].items) do
    local selected = e.selected and "+" or " "
    local mark = e.read and " " or "*"
    table.insert(lines, ("%s%s %s  %s  %s"):format(selected, mark, e.published:sub(1, 10), one_line(e.feed), one_line(e.title)))
  end
  set_lines(buf, #lines > 0 and lines or { "(no entries)" })
end

local function list_item(buf)
  local win = vim.fn.bufwinid(buf)
  if win == -1 or not state[buf] then
    return nil
  end
  return state[buf].items[vim.api.nvim_win_get_cursor(win)[1]]
end

local function focus_list()
  local buf = preview.list
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("leftabove vsplit")
    vim.api.nvim_win_set_buf(0, buf)
  end
end

local function setup_preview_keys(cfg)
  map(preview_buf(), cfg.keymaps.preview, {
    open_url = function()
      if preview.entry then
        open_urls({ preview.entry })
      end
    end,
    browser = render_in_browser,
    close = focus_list,
  })
end

-- A command run from the preview must not replace it with the list.
local function leave_preview()
  if vim.api.nvim_get_current_win() == preview_win() then
    vim.cmd("wincmd p")
    if vim.api.nvim_get_current_win() == preview_win() then
      vim.cmd("leftabove vsplit")
    end
  end
end

-- opts: {unread=, category=, collection=}; title names the buffer.
function M.timeline(opts, title)
  local cfg = require("folo").get_config()
  leave_preview()
  local buf = create_scratch("folo://timeline/" .. title, "folo-timeline")
  vim.api.nvim_set_current_buf(buf)
  vim.wo.wrap = false
  state[buf] = { items = {}, next = nil, loading = false }
  preview.list = buf
  ensure_preview_win(cfg)
  setup_preview_keys(cfg)

  local function preview_current()
    local e = list_item(buf)
    if e then
      preview.list = buf
      if preview.entry ~= e then
        show_preview(e)
      end
    end
  end

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
      if preview.list == buf then
        preview_current()
      end
    end
    if opts.collection then
      cli.collection({ cursor = cursor }, on_page)
    else
      cli.timeline({ unread = opts.unread, category = opts.category, cursor = cursor }, on_page)
    end
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

  vim.api.nvim_clear_autocmds({ group = vim.api.nvim_create_augroup("folo_list_" .. buf, {}) })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = "folo_list_" .. buf,
    buffer = buf,
    callback = function()
      local requested = list_item(buf)
      vim.defer_fn(function()
        if requested and requested == list_item(buf) then
          preview_current()
        end
      end, cfg.preview_debounce_ms)
    end,
  })

  map(buf, cfg.keymaps.list, {
    open = function()
      local e = list_item(buf)
      if not e then
        return
      end
      if not e.read then
        set_read(e, true)
      end
      preview.list = buf
      if preview.entry ~= e then
        show_preview(e)
      end
      vim.api.nvim_set_current_win(ensure_preview_win(cfg))
    end,
    toggle_select = function()
      local e = list_item(buf)
      if not e then
        return
      end
      e.selected = not e.selected or nil
      redraw(buf)
      local row = vim.api.nvim_win_get_cursor(0)[1]
      if row < vim.api.nvim_buf_line_count(buf) then
        vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
      end
    end,
    toggle_read = function()
      local e = list_item(buf)
      if e then
        set_read(e, not e.read)
      end
    end,
    -- Opens the selection, or the current entry when nothing is selected.
    open_url = function()
      local selected = vim.tbl_filter(function(e)
        return e.selected
      end, state[buf].items)
      if #selected == 0 then
        local e = list_item(buf)
        if e then
          open_urls({ e })
        end
        return
      end
      if open_urls(selected) then
        for _, e in ipairs(selected) do
          e.selected = nil
        end
        redraw(buf)
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
      preview.entry = nil
      load_page(nil)
    end,
    close = function()
      local win = preview_win()
      if win and #vim.api.nvim_tabpage_list_wins(0) > 1 then
        vim.api.nvim_win_close(win, true)
      end
      vim.cmd("bdelete")
    end,
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

return M
