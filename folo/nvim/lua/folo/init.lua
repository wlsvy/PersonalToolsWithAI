-- Options are documented in folo/docs/nvim.ai.md; keep both in sync.
local M = {}

local defaults = {
  cmd = { "folo" }, -- argv prefix, e.g. { "npx", "--yes", "folocli@0.0.5" }
  view = nil, -- nil = CLI default
  page_size = nil, -- nil = CLI default
  timeout_ms = 30000,
  render = "auto", -- "auto" | "pandoc" | "strip"
  keymaps = {
    timeline = { open = "<CR>", toggle_read = "m", open_url = "gx", next_page = "]p", refresh = "r", close = "q" },
    entry = { open_url = "gx", close = "q" },
  },
}

M.config = nil

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})
end

function M.get_config()
  if not M.config then
    M.setup()
  end
  return M.config
end

return M
