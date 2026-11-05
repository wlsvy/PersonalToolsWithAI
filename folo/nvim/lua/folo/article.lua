-- Fetches article pages. Only this module runs curl or a browser or inspects page HTML.
local M = {}

local USER_AGENT = "Mozilla/5.0 (compatible; folo.nvim)"
local REMOVED_BLOCKS = { "script", "style", "noscript", "svg", "iframe", "nav", "header", "footer", "aside", "form" }

local function is_private_ipv4(host)
  local a, b = host:match("^(%d+)%.(%d+)%.%d+%.%d+$")
  a, b = tonumber(a), tonumber(b)
  if not a then
    return false
  end
  return a == 0
    or a == 10
    or a == 127
    or (a == 100 and b >= 64 and b <= 127)
    or (a == 169 and b == 254)
    or (a == 172 and b >= 16 and b <= 31)
    or (a == 192 and b == 168)
end

-- shortcut: checks the URL's literal host, not DNS or redirects; pin resolved addresses if these
-- requests ever carry credentials.
function M.safe_url(url)
  if type(url) ~= "string" then
    return false, "no URL"
  end
  local scheme, rest = url:match("^(%a[%w+.-]*)://(.+)$")
  if not scheme or not vim.tbl_contains({ "http", "https" }, scheme:lower()) then
    return false, "only http and https URLs are fetched"
  end
  local authority = rest:match("^[^/?#]+") or ""
  local host = authority:gsub("^.*@", ""):lower()
  if host:sub(1, 1) == "[" then
    return false, "IPv6 literal hosts are not fetched"
  end
  host = host:gsub(":%d*$", ""):gsub("%.$", "")
  if host == "" or host == "localhost" or host:match("%.localhost$") or host:match("%.local$") or is_private_ipv4(host) then
    return false, "private network hosts are not fetched"
  end
  if host:match("^%d+$") or host:match("^0[xX]") then
    return false, "numeric hosts are not fetched"
  end
  return true
end

local function find_charset(html, content_type)
  local charset = (content_type or ""):lower():match("charset=[\"']?([%w_.:-]+)")
  return charset or html:sub(1, 4096):lower():match("<meta[^>]-charset=[\"']?([%w_.:-]+)")
end

local function to_utf8(html, content_type)
  local charset = find_charset(html, content_type)
  if charset and charset ~= "utf-8" and charset ~= "utf8" then
    local converted = vim.iconv(html, charset, "utf-8")
    if converted then
      return converted
    end
  end
  return html
end

-- Removes every <tag ...>...</tag>; an unclosed block runs to the end of the page.
local function remove_blocks(html, tag)
  local lower = html:lower()
  local parts, pos = {}, 1
  while true do
    local start = lower:find("<" .. tag .. "[%s>/]", pos)
    if not start then
      table.insert(parts, html:sub(pos))
      break
    end
    table.insert(parts, html:sub(pos, start - 1))
    local _, stop = lower:find("</" .. tag .. "%s*>", start)
    if not stop then
      break
    end
    pos = stop + 1
  end
  return table.concat(parts)
end

local function inner_blocks(html, tag)
  local lower = html:lower()
  local blocks, pos = {}, 1
  while true do
    local start = lower:find("<" .. tag .. "[%s>]", pos)
    if not start then
      return blocks
    end
    local open_end = lower:find(">", start, true)
    local close_start, close_end = lower:find("</" .. tag .. "%s*>", start)
    if not open_end or not close_start then
      return blocks
    end
    table.insert(blocks, html:sub(open_end + 1, close_start - 1))
    pos = close_end + 1
  end
end

function M.text_len(html)
  local text = (html or ""):gsub("<[^>]->", " "):gsub("%s+", " ")
  return vim.fn.strchars(vim.trim(text))
end

-- extract(html): the page's main content as UTF-8 HTML.
function M.extract(html, content_type)
  local cleaned = to_utf8(html, content_type)
  for _, tag in ipairs(REMOVED_BLOCKS) do
    cleaned = remove_blocks(cleaned, tag)
  end
  for _, tag in ipairs({ "article", "main", "body" }) do
    local best, best_len = nil, 0
    for _, block in ipairs(inner_blocks(cleaned, tag)) do
      local len = M.text_len(block)
      if len > best_len then
        best, best_len = block, len
      end
    end
    if best then
      return best
    end
  end
  return cleaned
end

local function config()
  return require("folo").get_config().article
end

-- fetch(url, cb(err, html)); cb runs on the main loop.
function M.fetch(url, cb)
  local safe, reason = M.safe_url(url)
  if not safe then
    return vim.schedule_wrap(cb)(reason)
  end
  local cfg = config()
  -- The trailer follows the body, so a page's own text cannot be mistaken for it.
  local cmd = {
    "curl", "-sSL", "--compressed",
    "--proto", "=http,https", "--proto-redir", "=http,https",
    "--max-time", tostring(cfg.curl_timeout_s),
    "--max-filesize", tostring(cfg.max_bytes),
    "-A", USER_AGENT,
    "-w", "\n%{http_code} %{content_type}",
    "--url", url,
  }
  local ok, err = pcall(vim.system, cmd, { text = false }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        return cb(("curl: %s"):format(vim.trim(res.stderr or "")))
      end
      local body, status, content_type = res.stdout:match("^(.*)\n(%d+) ([^\n]*)$")
      status = tonumber(status)
      if not status then
        return cb("unexpected curl output")
      end
      if status >= 400 then
        return cb(("HTTP %d"):format(status))
      end
      if not content_type:lower():find("html", 1, true) then
        return cb(("not an HTML page (%s)"):format(content_type))
      end
      cb(nil, M.extract(body, content_type))
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb("cannot run curl: " .. tostring(err))
    end)
  end
end

local function browser_cmd(cfg)
  if cfg.browser_cmd then
    return vim.deepcopy(cfg.browser_cmd)
  end
  local candidates = {
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    vim.fn.expand("~/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "google-chrome",
    "chromium",
    "chromium-browser",
  }
  for _, candidate in ipairs(candidates) do
    if vim.fn.executable(candidate) == 1 then
      return { candidate }
    end
  end
end

-- render_browser(url, cb(err, html)): for pages that need JavaScript. A throwaway profile keeps
-- the user's cookies and logins away from the page.
function M.render_browser(url, cb)
  local safe, reason = M.safe_url(url)
  if not safe then
    return vim.schedule_wrap(cb)(reason)
  end
  local cfg = config()
  local cmd = browser_cmd(cfg)
  if not cmd then
    return vim.schedule_wrap(cb)("no Chrome or Chromium found; set article.browser_cmd")
  end
  local profile = vim.fn.tempname()
  vim.list_extend(cmd, {
    "--headless=new", "--disable-gpu", "--no-first-run",
    "--user-data-dir=" .. profile, "--virtual-time-budget=5000", "--dump-dom", url,
  })
  local ok, err = pcall(vim.system, cmd, { text = false, timeout = cfg.browser_timeout_ms }, function(res)
    vim.schedule(function()
      vim.fn.delete(profile, "rf")
      if res.code == 124 then
        return cb("browser timed out")
      end
      if res.code ~= 0 or res.stdout == "" then
        return cb(("browser exit %d: %s"):format(res.code, vim.trim(res.stderr or ""):sub(1, 200)))
      end
      cb(nil, M.extract(res.stdout))
    end)
  end)
  if not ok then
    vim.schedule(function()
      vim.fn.delete(profile, "rf")
      cb("cannot run browser: " .. tostring(err))
    end)
  end
end

return M
