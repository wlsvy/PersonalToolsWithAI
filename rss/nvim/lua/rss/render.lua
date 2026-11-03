local M = {}

local entities = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }

-- shortcut: drops tables, links and lists formatting; install pandoc (render="auto") for real conversion.
function M.strip(html)
  local s = html:gsub("<[bB][rR]%s*/?>", "\n"):gsub("</[pP]>", "\n\n"):gsub("<[^>]->", "")
  s = s:gsub("&#(%d+);", function(n)
    return vim.fn.nr2char(tonumber(n))
  end)
  s = s:gsub("&(%a+);", function(name)
    return entities[name] or ("&" .. name .. ";")
  end)
  return vim.split(vim.trim(s), "\n", { plain = true })
end

-- to_lines(html, mode, cb(lines)); cb runs on the main loop.
function M.to_lines(html, mode, cb)
  local use_pandoc = mode == "pandoc" or (mode == "auto" and vim.fn.executable("pandoc") == 1)
  if not use_pandoc then
    return cb(M.strip(html))
  end
  vim.system({ "pandoc", "-f", "html", "-t", "gfm-raw_html", "--wrap=none" }, { text = true, stdin = html }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        return cb(M.strip(html))
      end
      cb(vim.split(vim.trim(res.stdout), "\n", { plain = true }))
    end)
  end)
end

return M
