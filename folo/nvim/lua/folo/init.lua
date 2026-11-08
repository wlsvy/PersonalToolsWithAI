-- Options are documented in folo/docs/nvim.ai.md; keep both in sync.
local M = {}

local defaults = {
  cmd = { "folo" }, -- argv prefix, e.g. { "npx", "--yes", "folocli@0.0.5" }
  view = nil, -- nil = CLI default
  page_size = nil, -- nil = CLI default
  timeout_ms = 30000,
  render = "auto", -- "auto" | "pandoc" | "strip"
  list_width = 0.4, -- fraction of the tab, or columns when >= 1
  preview_debounce_ms = 150,
  lazy_load_margin = 5, -- load the next page within this many rows of the end; 0 = off
  open_confirm_over = 10, -- confirm before opening more URLs than this
  icons = {
    enabled = true,
    default = "📰", -- unmatched host or no URL
    -- lowercase host without "www."; subdomains inherit; false drops a default
    domains = {
      ["github.com"] = "🐙",
      ["youtube.com"] = "📺",
      ["reddit.com"] = "👽",
      ["news.ycombinator.com"] = "🟧",
      ["medium.com"] = "✍️",
      ["substack.com"] = "📮",
      ["arxiv.org"] = "📄",
      ["x.com"] = "🐦",
      ["twitter.com"] = "🐦",
    },
  },
  article = {
    auto_fetch = true, -- false: no automatic curl; Folo readability still runs
    thin_chars = 200, -- feed body shorter than this (text chars) triggers the fetch chain
    curl_timeout_s = 15,
    max_bytes = 5 * 1024 * 1024,
    browser_cmd = nil, -- argv prefix; nil = detect Chrome/Chromium
    browser_timeout_ms = 30000,
  },
  ai = {
    cmd = { "claude" },
    config_dir = "~/.claude-clip", -- CLAUDE_CONFIG_DIR, shared with native-host
    models = { summary = "sonnet", translation = "sonnet" },
    prompts = {}, -- { summary = path, translation = path }; default native-host/prompts/*.md
    concurrency = 3,
    timeout_ms = { summary = 600000, translation = 1800000 },
    confirm_over = 10, -- confirm before queueing more entries than this
    dir = nil, -- default stdpath("cache")/folo/summaries
  },
  keymaps = {
    list = {
      open = "<CR>",
      toggle_select = "<Tab>",
      toggle_read = "m",
      toggle_star = "S",
      open_url = "gx",
      next_page = "]p",
      refresh = "r",
      summarize = "s",
      translate = "t",
      delete_summary = "x",
      close = "q",
      help = "?",
    },
    preview = { open_url = "gx", browser = "R", close = "q", help = "?" },
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
