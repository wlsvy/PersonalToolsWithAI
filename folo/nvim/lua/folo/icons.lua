-- Site icons for list rows, looked up by host in config.icons.domains.
local M = {}

local function host(url)
  local h = (url or ""):match("^%a[%w+.-]*://([^/?#]+)")
  if not h then
    return nil
  end
  h = h:gsub("^.*@", ""):gsub(":%d*$", ""):lower()
  return (h:gsub("^www%.", ""))
end

-- Two letters of the site's name. Hosts come from feeds, so only %w reaches the row.
-- shortcut: no public suffix list, upgrade if badges for ccTLD hosts look wrong.
local function badge(h)
  if not h or not h:find(".", 1, true) or h:match("^[%d.]+$") then
    return nil
  end
  local labels = vim.split(h, ".", { plain = true })
  local n = #labels
  local i = (n >= 3 and #labels[n] == 2 and #labels[n - 1] <= 3) and n - 2 or n - 1
  local text = labels[i]:match("^%w%w?")
  return text and text:upper()
end

local function palette_color(h, palette)
  if #palette == 0 then
    return nil
  end
  local sum = 0
  for i = 1, #h do
    sum = sum + h:byte(i)
  end
  return palette[sum % #palette + 1]
end

-- for_entry(e) -> icon, color; prefers the feed's site, then the entry URL. Subdomains inherit.
function M.for_entry(e)
  local cfg = require("folo").get_config().icons
  local full = host(e.site ~= "" and e.site or e.url)
  local h = full
  local icon, color
  while h and h:find(".", 1, true) do
    local value = cfg.domains[h]
    if type(value) == "table" then
      icon, color = value[1], value.color
      break
    elseif value then
      icon = value
      break
    end
    h = h:gsub("^[^.]*%.", "", 1)
  end
  icon = icon or badge(full)
  if not icon then
    return cfg.default, color
  end
  return icon, color or palette_color(full, cfg.palette)
end

return M
