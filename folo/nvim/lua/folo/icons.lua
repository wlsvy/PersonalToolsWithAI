-- Site emoji for list rows, looked up by host in config.icons.domains.
local M = {}

local function host(url)
  local h = (url or ""):match("^%a[%w+.-]*://([^/?#]+)")
  if not h then
    return nil
  end
  h = h:gsub("^.*@", ""):gsub(":%d*$", ""):lower()
  return (h:gsub("^www%.", ""))
end

-- for_entry(e) -> emoji; prefers the feed's site, then the entry URL. Subdomains inherit.
function M.for_entry(e)
  local cfg = require("folo").get_config().icons
  local h = host(e.site ~= "" and e.site or e.url)
  while h and h:find(".", 1, true) do
    local icon = cfg.domains[h]
    if icon then
      return icon
    end
    h = h:gsub("^[^.]*%.", "", 1)
  end
  return cfg.default
end

return M
