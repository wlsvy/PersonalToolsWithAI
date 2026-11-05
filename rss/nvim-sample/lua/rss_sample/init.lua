-- Options are documented in rss/docs/config.ai.md; keep both in sync.
local M = {}

local defaults = {
  url = nil,
  token = nil,
  api_base = "/api/v1",
  page_size = nil, -- nil = server default
  render = "auto", -- "auto" | "pandoc" | "strip"
  keymaps = {
    feeds = { open = "<CR>", refresh = "r", delete = "dd", close = "q" },
    entries = {
      open = "<CR>",
      toggle_read = "m",
      toggle_star = "s",
      open_url = "gx",
      next_page = "]p",
      close = "q",
    },
    entry = { open_url = "gx", close = "q" },
  },
}

M.config = nil

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, { url = vim.env.RSS_URL, token = vim.env.RSS_TOKEN }, opts or {})
end

-- Returns the config, or nil after notifying when url/token are missing.
function M.get_config()
  if not M.config then
    M.setup()
  end
  if not M.config.url or not M.config.token then
    vim.notify("rss_sample: set url and token via require('rss_sample').setup{} or RSS_URL/RSS_TOKEN", vim.log.levels.ERROR)
    return nil
  end
  return M.config
end

return M
