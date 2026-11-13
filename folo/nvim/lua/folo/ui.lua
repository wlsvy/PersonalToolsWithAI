local ai = require("folo.ai")
local article = require("folo.article")
local cli = require("folo.cli")
local icons = require("folo.icons")
local render = require("folo.render")

local M = {}

local PREVIEW_NAME = "folo://preview"
local STAR = "\u{f005}" -- nf-fa-star
local ICON_NS = vim.api.nvim_create_namespace("folo_icons")
local DASHBOARD_NAME = "Folo Dashboard"
local DASHBOARD_NS = vim.api.nvim_create_namespace("folo_dashboard")
local HEADER_NAME = "folo://header"
local HEADER_NS = vim.api.nvim_create_namespace("folo_header")
-- Kept here: a name without a scheme is stored as a full path, so find_buf cannot match it.
local dashboard_buf
local header_buf

-- Per-list state, keyed by bufnr.
local state = {}
-- Finished previews by entry id, kept for the session.
local cache = {}
-- The list driving the preview, and a counter that makes older async results stale.
local preview = { list = nil, entry = nil, child = false, generation = 0 }

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

local function show_article(view, wanted, html, source, finish)
  render.to_lines(html, require("folo").get_config().render, function(lines)
    if not wanted() then
      return
    end
    view.article, view.source, view.status = lines, source, nil
    finish()
  end)
end

local function article_failed(view, reason)
  view.status = ("Could not load article: %s. Press R to render in a browser."):format(reason)
end

local function fetch_with_curl(view, wanted, finish)
  article.fetch(view.entry.url, function(err, html)
    if not wanted() then
      return
    end
    if err then
      article_failed(view, err)
      return finish()
    end
    show_article(view, wanted, html, "curl", finish)
  end)
end

-- Feed body is kept; thin bodies get the article appended below it.
local function fetch_article(view, wanted, on_update, finish)
  local cfg = require("folo").get_config().article
  cli.readability(view.entry.id, function(err, content)
    if not wanted() then
      return
    end
    if not err and article.text_len(content) >= cfg.thin_chars then
      return show_article(view, wanted, content, "Folo", finish)
    end
    if cfg.auto_fetch then
      view.status = "Loading article…"
      on_update(view)
      return fetch_with_curl(view, wanted, finish)
    end
    article_failed(view, err or "no readable content")
    finish()
  end)
end

-- Runs the content chain. wanted() false stops it early; on_done gets the view, with
-- view.error when the entry itself could not be loaded (those views are not cached).
local function load_view(e, wanted, on_update, on_done)
  if cache[e.id] then
    return on_done(cache[e.id])
  end
  local view = { entry = e, status = "Loading…" }
  on_update(view)
  local cfg = require("folo").get_config()
  cli.entry(e.id, function(err, full)
    if not wanted() then
      return
    end
    if err then
      view.status, view.error = err, err
      return on_done(view)
    end
    local html = full.content or ""
    render.to_lines(html, cfg.render, function(body)
      if not wanted() then
        return
      end
      view.body, view.status = body, nil
      local function finish()
        cache[e.id] = view
        on_done(view)
      end
      if article.text_len(html) >= cfg.article.thin_chars then
        return finish()
      end
      view.status = "Loading article…"
      on_update(view)
      fetch_article(view, wanted, on_update, finish)
    end)
  end)
end

local function next_generation()
  preview.generation = preview.generation + 1
  local generation = preview.generation
  return function()
    return preview.generation == generation
  end
end

local function show_preview(e)
  local wanted = next_generation()
  preview.entry, preview.child = e, false
  local function draw(view)
    if wanted() then
      draw_preview(view)
    end
  end
  load_view(e, wanted, draw, draw)
end

local function render_in_browser()
  local e = preview.entry
  if not e then
    return
  end
  local wanted = next_generation()
  preview.child = false
  local view = cache[e.id] or { entry = e }
  view.status = "Rendering in a headless browser…"
  draw_preview(view)
  article.render_browser(e.url, function(err, html)
    if not wanted() then
      return
    end
    if err then
      view.status = "Browser render failed: " .. err
      return draw_preview(view)
    end
    show_article(view, wanted, html, "browser", function()
      cache[e.id] = view
      draw_preview(view)
    end)
  end)
end

-- AI --------------------------------------------------------------------

-- ai_source(e, cb(err, markdown)): the text sent to Claude.
local function ai_source(e, cb)
  local function always()
    return true
  end
  load_view(e, always, function() end, function(view)
    if view.error then
      return cb(view.error)
    end
    local content = vim.deepcopy(view.body or {})
    vim.list_extend(content, view.article or {})
    local text = vim.trim(table.concat(content, "\n"))
    local thin_chars = require("folo").get_config().article.thin_chars
    -- A link alone would invite the model to invent the article.
    if not view.article and vim.fn.strchars(text) < thin_chars then
      return cb("article could not be loaded; press R on the entry's preview, then retry")
    end
    cb(nil, ("# %s\n\n%s\n\n%s"):format(one_line(e.title), e.url, text))
  end)
end

local function ai_progress(info)
  if info.summary then
    return "Summary " .. info.summary .. "…"
  end
  if info.translation then
    return "Translation " .. info.translation .. "…"
  end
  return info.error and ("Failed: " .. info.error) or nil
end

local function draw_summary(e)
  local lines = ai.read(e.id) or { "# " .. one_line(e.title), "" }
  local progress = ai_progress(ai.info(e.id))
  if progress then
    vim.list_extend(lines, { "", "> " .. progress })
  end
  set_lines(preview_buf(), lines)
  local win = preview_win()
  if win then
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
  end
end

local function show_summary(e)
  next_generation()
  preview.entry, preview.child = e, true
  draw_summary(e)
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

-- Help ------------------------------------------------------------------

local HELP = {
  list = {
    title = " Folo list ",
    notes = {
      "Moving the cursor previews an entry without marking it read.",
      "Row marks: + selected, * unread, " .. STAR .. " starred. Summaries appear as child rows.",
      function(cfg)
        return ("Pages: %s entries per load, newest first by publish time."):format(cfg.page_size or "20 (CLI default)")
      end,
      "The starred list is newest first by star time; rows show the publish date.",
      function(cfg)
        if cfg.lazy_load_margin > 0 then
          return ("The next page loads when the cursor is within %d rows of the end."):format(cfg.lazy_load_margin)
        end
        return "Auto paging is off; load pages with " .. (cfg.keymaps.list.next_page or "next_page") .. "."
      end,
    },
    keys = {
      { "open", "Mark read and focus the preview" },
      { "toggle_select", "Select or unselect, then move down" },
      { "toggle_read", "Toggle read on selected entries, or the current one" },
      { "toggle_star", "Star or unstar selected entries, or the current one" },
      { "open_url", "Open selected entries on the web, or the current one" },
      { "summarize", "AI summary of selected entries, or the current one" },
      { "translate", "AI translation appended below the summary" },
      { "delete_summary", "Delete the entry's summary file" },
      { "next_page", "Load the next page" },
      { "refresh", "Reload from the first page" },
      { "close", "Close the list and go to the dashboard" },
      { "help", "Toggle this help" },
    },
  },
  dashboard = {
    title = " Folo dashboard ",
    notes = { "Counts are unread entries in the configured view." },
    keys = {
      { "open", "Open unread entries of the category or feed" },
      { "refresh", "Reload the counts" },
      { "close", "Close the dashboard tab" },
      { "help", "Toggle this help" },
    },
  },
  preview = {
    title = " Folo preview ",
    notes = { "Short feed bodies get the article appended (Folo, then curl)." },
    keys = {
      { "open_url", "Open the entry on the web" },
      { "browser", "Render the article in a headless browser" },
      { "close", "Back to the list" },
      { "help", "Toggle this help" },
    },
  },
}

local help = { win = nil, kind = nil }

local function close_help()
  if help.win and vim.api.nvim_win_is_valid(help.win) then
    vim.api.nvim_win_close(help.win, true)
  end
  help.win, help.kind = nil, nil
end

local function help_lines(kind)
  local cfg = require("folo").get_config()
  local keymaps = cfg.keymaps[kind]
  local rows = {}
  local key_width = 0
  for _, item in ipairs(HELP[kind].keys) do
    -- Built from the live keymaps so remapped or disabled keys stay accurate.
    local key = keymaps[item[1]]
    if key then
      table.insert(rows, { key, item[2] })
      key_width = math.max(key_width, vim.fn.strdisplaywidth(key))
    end
  end
  local lines = {}
  for _, row in ipairs(rows) do
    local padding = (" "):rep(key_width - vim.fn.strdisplaywidth(row[1]))
    table.insert(lines, (" %s%s  %s "):format(row[1], padding, row[2]))
  end
  table.insert(lines, "")
  for _, note in ipairs(HELP[kind].notes) do
    -- Function notes read live config values.
    note = type(note) == "function" and note(cfg) or note
    table.insert(lines, " " .. note .. " ")
  end
  return lines
end

-- The popup never takes focus, so the same key closes it and navigation keeps working.
local function toggle_help(kind)
  local same = help.kind == kind and help.win and vim.api.nvim_win_is_valid(help.win)
  close_help()
  if same then
    return
  end
  local lines = help_lines(kind)
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  help.win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    anchor = "NE",
    row = 1,
    col = vim.o.columns - 1,
    width = math.min(width, math.max(1, vim.o.columns - 4)),
    height = math.min(#lines, math.max(1, vim.o.lines - 5)),
    style = "minimal",
    border = "rounded",
    title = HELP[kind].title,
    focusable = false,
    zindex = 60,
  })
  vim.wo[help.win].wrap = true
  help.kind = kind
end

-- List ------------------------------------------------------------------

local function child_text(info)
  if info.error then
    return "failed: " .. one_line(info.error)
  end
  local parts = {}
  if info.summary then
    table.insert(parts, "summary " .. info.summary)
  elseif info.has_summary then
    table.insert(parts, "summary")
  end
  if info.translation then
    table.insert(parts, "translation " .. info.translation)
  elseif info.has_translation then
    table.insert(parts, "translation")
  end
  return table.concat(parts, " + ")
end

local function same_row(a, b)
  return a.entry == b.entry and a.child == b.child
end

local function redraw(buf)
  local s = state[buf]
  local win = vim.fn.bufwinid(buf)
  local current = win ~= -1 and s.rows[vim.api.nvim_win_get_cursor(win)[1]] or nil
  local lines, rows, colored = {}, {}, {}
  local icons_on = require("folo").get_config().icons.enabled
  for _, e in ipairs(s.items) do
    local selected = e.selected and "+" or " "
    local mark = e.read and " " or "*"
    local star = e.starred and STAR or " "
    local prefix = ("%s%s %s "):format(selected, mark, star)
    local cell = ""
    if icons_on then
      local icon, color = icons.for_entry(e)
      -- Glyphs take one cell and badges two; a fixed column keeps the rows aligned.
      cell = icon .. (" "):rep(2 - vim.fn.strdisplaywidth(icon)) .. " "
      if type(color) == "string" and color:match("^#%x%x%x%x%x%x$") then
        table.insert(colored, { row = #lines, col = #prefix, end_col = #prefix + #icon, color = color })
      end
    end
    table.insert(lines, ("%s%s%s  %s  %s"):format(prefix, cell, e.published:sub(1, 10), one_line(e.feed), one_line(e.title)))
    table.insert(rows, { entry = e, child = false })
    local info = ai.info(e.id)
    if info.visible then
      table.insert(lines, "   └ " .. child_text(info))
      table.insert(rows, { entry = e, child = true })
    end
  end
  s.rows = rows
  set_lines(buf, #lines > 0 and lines or { "(no entries)" })
  vim.api.nvim_buf_clear_namespace(buf, ICON_NS, 0, -1)
  for _, c in ipairs(colored) do
    local group = "FoloIcon" .. c.color:sub(2)
    -- Set on every redraw so a colorscheme change recovers.
    vim.api.nvim_set_hl(0, group, { fg = c.color })
    vim.api.nvim_buf_set_extmark(buf, ICON_NS, c.row, c.col, { end_col = c.end_col, hl_group = group })
  end
  -- Child rows shift everything below them; stay on the same item.
  if current then
    -- A removed child row falls back to its entry.
    local target
    for i, row in ipairs(rows) do
      if same_row(row, current) then
        target = i
        break
      elseif row.entry == current.entry and not row.child then
        target = i
      end
    end
    if target then
      vim.api.nvim_win_set_cursor(win, { target, 0 })
    end
  end
end

local function list_row(buf)
  local win = vim.fn.bufwinid(buf)
  if win == -1 or not state[buf] then
    return nil
  end
  return state[buf].rows[vim.api.nvim_win_get_cursor(win)[1]]
end

local function list_item(buf)
  local row = list_row(buf)
  return row and row.entry
end

local function show_row(row)
  if row.child then
    if not (preview.child and preview.entry == row.entry) then
      show_summary(row.entry)
    end
  elseif preview.child or preview.entry ~= row.entry then
    show_preview(row.entry)
  end
end

ai.on_change(function(id)
  for buf in pairs(state) do
    if vim.api.nvim_buf_is_valid(buf) then
      redraw(buf)
    end
  end
  if preview.child and preview.entry and preview.entry.id == id then
    draw_summary(preview.entry)
  end
end)

local function focus_list()
  close_help()
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

local map_nav

local function setup_preview_keys(cfg)
  map_nav(preview_buf())
  map(preview_buf(), cfg.keymaps.preview, {
    open_url = function()
      if preview.entry then
        open_urls({ preview.entry })
      end
    end,
    browser = render_in_browser,
    close = focus_list,
    help = function()
      toggle_help("preview")
    end,
  })
end

-- Folo tab --------------------------------------------------------------
-- One tab holds every panel: a one-line header of badges on top, the panel
-- (dashboard or a list) below it, and the preview to the right of a list.

local RIM_LEFT, RIM_RIGHT = "\u{e0b6}", "\u{e0b4}" -- nf-ple-left/right_half_circle_thick
local ACCENT = "#61afef"

local function darken(hex, f)
  local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
  if not r then
    return hex
  end
  local function ch(c)
    return math.floor(tonumber(c, 16) * f)
  end
  return ("#%02x%02x%02x"):format(ch(r), ch(g), ch(b))
end

-- Collects one line of text plus highlight spans in byte columns.
local function line_builder()
  local b = { text = "", spans = {} }
  function b.add(text, group)
    if group then
      table.insert(b.spans, { col = #b.text, end_col = #b.text + #text, group = group })
    end
    b.text = b.text .. text
  end
  -- Rounded caps in the rim color around a darker body of the same hue; active fills it.
  function b.badge(text, color, active)
    local hex = color:sub(2)
    local body = (active and "FoloBadgeOn" or "FoloBadge") .. hex
    -- Set on every draw so a colorscheme change recovers.
    vim.api.nvim_set_hl(0, "FoloRim" .. hex, { fg = color })
    if active then
      vim.api.nvim_set_hl(0, body, { fg = darken(color, 0.2), bg = color, bold = true })
    else
      vim.api.nvim_set_hl(0, body, { fg = color, bg = darken(color, 0.3), bold = true })
    end
    b.add(RIM_LEFT, "FoloRim" .. hex)
    b.add(" " .. text .. " ", body)
    b.add(RIM_RIGHT, "FoloRim" .. hex)
  end
  return b
end

local function draw_lines(buf, ns, built)
  local lines = {}
  for i, b in ipairs(built) do
    lines[i] = b.text
  end
  set_lines(buf, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, b in ipairs(built) do
    for _, sp in ipairs(b.spans) do
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, sp.col, { end_col = sp.end_col, hl_group = sp.group })
    end
  end
end

local NAV = {
  { "dashboard", "Dashboard" },
  { "timeline", "Timeline" },
  { "unread", "Unread" },
  { "starred", "Starred" },
  { "category", "Category" },
}

local function draw_header()
  if not (header_buf and vim.api.nvim_buf_is_valid(header_buf)) then
    return
  end
  local cfg = require("folo").get_config()
  local palette = cfg.icons.palette
  local b = line_builder()
  b.add(" ")
  for i, item in ipairs(NAV) do
    local key = cfg.keymaps.nav[item[1]]
    if key then
      b.add(" ")
      local color = palette[(i - 1) % math.max(1, #palette) + 1] or ACCENT
      b.badge(("%s (%s)"):format(item[2], key), color, vim.t.folo_panel == item[1])
    end
  end
  draw_lines(header_buf, HEADER_NS, { b })
end

-- Nav keys work from the header and every panel.
function map_nav(buf)
  local cfg = require("folo").get_config()
  -- M.* are defined further down; look them up at call time.
  map(buf, cfg.keymaps.nav, {
    dashboard = function()
      M.dashboard()
    end,
    timeline = function()
      M.timeline({}, "all")
    end,
    unread = function()
      M.timeline({ unread = true }, "unread")
    end,
    starred = function()
      M.starred()
    end,
    category = function()
      M.pick_category()
    end,
  })
end

local function header_win()
  local win = header_buf and vim.api.nvim_buf_is_valid(header_buf) and vim.fn.bufwinid(header_buf)
  return win and win ~= -1 and win or nil
end

-- The panel window: any window of the tab that is neither the header nor the preview.
local function main_win()
  local skip = { [header_win() or 0] = true, [preview_win() or 0] = true }
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not skip[win] and vim.api.nvim_win_get_config(win).relative == "" then
      return win
    end
  end
end

-- Goes to the Folo tab (making it when missing), focuses the panel window and marks `panel` active.
local function enter_tab(panel)
  close_help()
  local tab
  for _, t in ipairs(vim.api.nvim_list_tabpages()) do
    if vim.t[t].folo_dashboard then
      tab = t
    end
  end
  if tab then
    vim.api.nvim_set_current_tabpage(tab)
  else
    vim.cmd("tabnew")
    vim.bo.bufhidden = "wipe" -- the empty buffer goes away once a panel replaces it
    vim.t.folo_dashboard = true
    vim.t.tabname = DASHBOARD_NAME -- read by tabline plugins; the default tabline shows the buffer name
  end
  if not (header_buf and vim.api.nvim_buf_is_valid(header_buf)) then
    header_buf = create_scratch(HEADER_NAME, "folo-header")
    map_nav(header_buf)
  end
  if not header_win() then
    local cur = vim.api.nvim_get_current_win()
    vim.cmd("topleft 1split")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, header_buf)
    vim.wo[win].winfixheight = true
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].cursorline = false
    vim.wo[win].wrap = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldcolumn = "0"
    pcall(function()
      vim.wo[win].winfixbuf = true -- 0.10+: keeps :e and friends out of the header
    end)
    vim.api.nvim_set_current_win(cur)
  end
  local win = main_win()
  if not win then
    vim.cmd("botright new")
    win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_set_current_win(win)
  vim.t.folo_panel = panel
  draw_header()
end


local PANELS = { all = "timeline", unread = "unread", starred = "starred", category = "category" }

-- opts: {unread=, category=, feed=, collection=}; title names the buffer, its first part the active badge.
function M.timeline(opts, title)
  local cfg = require("folo").get_config()
  -- Runs from any window, the preview included; the list always lands in the panel window.
  enter_tab(PANELS[title:match("^[^/]+")])
  local buf = create_scratch("folo://timeline/" .. title, "folo-timeline")
  map_nav(buf)
  vim.api.nvim_set_current_buf(buf)
  vim.wo.wrap = false
  state[buf] = { items = {}, rows = {}, ids = {}, next = nil, loading = false }
  preview.list = buf
  ensure_preview_win(cfg)
  setup_preview_keys(cfg)

  local function preview_current()
    local row = list_row(buf)
    if row then
      preview.list = buf
      show_row(row)
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
      -- The cursor is a timestamp, so a page boundary can repeat entries.
      for _, e in ipairs(page.entries) do
        if not s.ids[e.id] then
          s.ids[e.id] = true
          table.insert(s.items, e)
        end
      end
      s.next = page.next
      redraw(buf)
      if preview.list == buf then
        preview_current()
      end
    end
    if opts.collection then
      cli.collection({ cursor = cursor }, on_page)
    else
      cli.timeline({ unread = opts.unread, category = opts.category, feed = opts.feed, cursor = cursor }, on_page)
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

  local function set_starred(e, starred)
    cli.set_starred(e.id, starred, function(err)
      if err then
        return notify_err(err)
      end
      e.starred = starred
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
      local s = state[buf]
      local m = cfg.lazy_load_margin
      if m > 0 and s.next and vim.api.nvim_win_get_cursor(0)[1] > #s.rows - m then
        load_page(s.next)
      end
      local requested = list_row(buf)
      vim.defer_fn(function()
        local row = list_row(buf)
        if requested and row and same_row(requested, row) then
          preview_current()
        end
      end, cfg.preview_debounce_ms)
    end,
  })

  local function targets()
    local selected = vim.tbl_filter(function(e)
      return e.selected
    end, state[buf].items)
    if #selected > 0 then
      return selected, true
    end
    local e = list_item(buf)
    return e and { e } or {}, false
  end

  local function queue(kind)
    local entries, from_selection = targets()
    if #entries > cfg.ai.confirm_over then
      if vim.fn.confirm(("Queue %d entries for AI?"):format(#entries), "&Yes\n&No", 2) ~= 1 then
        return
      end
    end
    local queued = 0
    for _, e in ipairs(entries) do
      if ai.enqueue(kind, e, ai_source) then
        queued = queued + 1
      end
    end
    if from_selection then
      for _, e in ipairs(entries) do
        e.selected = nil
      end
    end
    redraw(buf)
    vim.notify(("folo: queued %d, skipped %d already done or running"):format(queued, #entries - queued))
  end

  map(buf, cfg.keymaps.list, {
    summarize = function()
      queue("summary")
    end,
    translate = function()
      queue("translation")
    end,
    delete_summary = function()
      local e = list_item(buf)
      if not e or not ai.info(e.id).visible then
        return
      end
      if vim.fn.confirm("Delete this summary?", "&Yes\n&No", 2) ~= 1 then
        return
      end
      if not ai.remove(e.id) then
        vim.notify("folo: wait for the running AI job to finish")
      end
    end,
    open = function()
      local row = list_row(buf)
      if not row then
        return
      end
      if not row.entry.read then
        set_read(row.entry, true)
      end
      preview.list = buf
      show_row(row)
      close_help()
      vim.api.nvim_set_current_win(ensure_preview_win(cfg))
    end,
    toggle_select = function()
      local e = list_item(buf)
      if not e then
        return
      end
      e.selected = not e.selected or nil
      redraw(buf)
      -- Child rows belong to their entry, so the next stop is the next entry.
      local rows = state[buf].rows
      local row = vim.api.nvim_win_get_cursor(0)[1] + 1
      while rows[row] and rows[row].child do
        row = row + 1
      end
      if rows[row] then
        vim.api.nvim_win_set_cursor(0, { row, 0 })
      end
    end,
    -- Marks all targets read unless every one is already read.
    toggle_read = function()
      local entries, from_selection = targets()
      local want = false
      for _, e in ipairs(entries) do
        want = want or not e.read
      end
      for _, e in ipairs(entries) do
        if e.read ~= want then
          set_read(e, want)
        end
        if from_selection then
          e.selected = nil
        end
      end
      redraw(buf)
    end,
    -- Stars all targets unless every one is already starred.
    toggle_star = function()
      local entries, from_selection = targets()
      local want = false
      for _, e in ipairs(entries) do
        want = want or not e.starred
      end
      for _, e in ipairs(entries) do
        if e.starred ~= want then
          set_starred(e, want)
        end
        if from_selection then
          e.selected = nil
        end
      end
      redraw(buf)
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
      state[buf].rows = {}
      state[buf].ids = {}
      state[buf].next = nil
      preview.entry = nil
      load_page(nil)
    end,
    help = function()
      toggle_help("list")
    end,
    close = function()
      M.dashboard()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.cmd("bdelete " .. buf)
      end
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

-- Dashboard -------------------------------------------------------------

local function draw_dashboard(buf, data, err)
  local built, rows = {}, {}
  local function push(b, row)
    table.insert(built, b)
    rows[#built] = row
  end

  if not data then
    local b = line_builder()
    b.add("  " .. (err and ("Error: " .. err) or "Loading…"), err and "ErrorMsg" or "Comment")
    push(b)
  else
    local total = line_builder()
    total.add("  Unread  ", "Title")
    total.badge(tostring(data.total), ACCENT)
    push(total)

    local groups, by_name = {}, {}
    for _, it in ipairs(data.items) do
      local name = (it.category and it.category ~= "") and it.category or nil
      local g = by_name[name or ""]
      if not g then
        g = { name = name, count = 0, feeds = {} }
        by_name[name or ""] = g
        table.insert(groups, g)
      end
      g.count = g.count + it.count
      table.insert(g.feeds, it)
    end
    local function by_count(a, b)
      return a.count > b.count
    end
    table.sort(groups, by_count)
    for _, g in ipairs(groups) do
      table.sort(g.feeds, by_count)
      push(line_builder())
      local h = line_builder()
      h.add("  " .. (g.name or "Uncategorized") .. "  ", "Title")
      h.badge(tostring(g.count), ACCENT)
      -- No CLI filter selects feeds without a category, so that header opens nothing.
      push(h, g.name and { category = g.name } or nil)
      for _, f in ipairs(g.feeds) do
        local title = one_line(f.title)
        local row = line_builder()
        -- ponytail: fixed title column; long titles push the count right.
        row.add("    " .. title .. (" "):rep(math.max(2, 50 - vim.fn.strdisplaywidth(title))))
        row.add(tostring(f.count), "Number")
        push(row, { feed = f.feed, title = title })
      end
    end
    if #groups == 0 then
      push(line_builder())
      local b = line_builder()
      b.add("  Nothing unread.", "Comment")
      push(b)
    end
  end

  draw_lines(buf, DASHBOARD_NS, built)
  state[buf] = { rows = rows }
end

local function refresh_dashboard(buf)
  draw_dashboard(buf, nil)
  cli.unread(function(err, data)
    if vim.api.nvim_buf_is_valid(buf) then
      draw_dashboard(buf, data, err)
    end
  end)
end

-- Shows the dashboard in the Folo tab's panel window.
function M.dashboard()
  local cfg = require("folo").get_config()
  enter_tab("dashboard")
  local win = preview_win()
  if win then
    vim.api.nvim_win_close(win, true)
  end
  if not (dashboard_buf and vim.api.nvim_buf_is_valid(dashboard_buf)) then
    dashboard_buf = create_scratch(DASHBOARD_NAME, "folo-dashboard")
  end
  local buf = dashboard_buf
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.wrap = false
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.cursorline = true

  map_nav(buf)
  map(buf, cfg.keymaps.dashboard, {
    open = function()
      local s = state[buf]
      local row = s and s.rows[vim.api.nvim_win_get_cursor(0)[1]]
      if not row then
        return
      end
      if row.category then
        M.timeline({ unread = true, category = row.category }, "unread/category/" .. row.category)
      else
        M.timeline({ unread = true, feed = row.feed }, "unread/feed/" .. row.title)
      end
    end,
    refresh = function()
      refresh_dashboard(buf)
    end,
    close = function()
      close_help()
      if #vim.api.nvim_list_tabpages() > 1 then
        vim.cmd("tabclose")
      else
        -- Last tab: drop the Folo layout and leave a plain window behind.
        vim.t.folo_dashboard = nil
        vim.cmd("only")
        vim.cmd("bdelete")
      end
    end,
    help = function()
      toggle_help("dashboard")
    end,
  })
  refresh_dashboard(buf)
end

return M
