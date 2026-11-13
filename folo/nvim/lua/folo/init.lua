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
    default = "\u{f09e}", -- nf-fa-rss; no usable host
    -- Sites with no color of their own pick one of these by host.
    palette = { "#e06c75", "#d19a66", "#98c379", "#56b6c2", "#61afef", "#c678dd", "#e5a50a", "#2aa198" },
    -- lowercase host without "www."; subdomains inherit; false drops a default
    -- Value: icon string, or { icon, color = "#rrggbb" }. Omit the icon to keep the
    -- two-letter badge that hosts outside this table get.
    domains = {
      ["github.com"] = "\u{f09b}", -- nf-fa-github
      ["youtube.com"] = { "\u{f16a}", color = "#ff4040" }, -- nf-fa-youtube_play
      ["reddit.com"] = { "\u{f281}", color = "#ff4500" }, -- nf-fa-reddit_alien
      ["news.ycombinator.com"] = { "\u{f1d4}", color = "#ff6600" }, -- nf-fa-hacker_news
      ["medium.com"] = "\u{f23a}", -- nf-fa-medium
      ["substack.com"] = { "\u{f0e0}", color = "#ff6719" }, -- nf-fa-envelope
      ["arxiv.org"] = { "\u{f0f6}", color = "#b31b1b" }, -- nf-fa-file_text_o
      ["x.com"] = { "\u{f099}", color = "#1d9bf0" }, -- nf-fa-twitter
      ["twitter.com"] = { "\u{f099}", color = "#1d9bf0" }, -- nf-fa-twitter
      ["t.me"] = { "\u{f2c6}", color = "#2aabee" }, -- nf-fa-telegram
      ["linkedin.com"] = { "\u{f0e1}", color = "#3b82c4" }, -- nf-fa-linkedin
      ["instagram.com"] = { "\u{f16d}", color = "#e1306c" }, -- nf-fa-instagram
      ["facebook.com"] = { "\u{f09a}", color = "#4c8bf5" }, -- nf-fa-facebook
      ["stackoverflow.com"] = { "\u{f16c}", color = "#f48024" }, -- nf-fa-stack_overflow
      ["apple.com"] = "\u{f179}", -- nf-fa-apple
      ["google.com"] = { "\u{f1a0}", color = "#4285f4" }, -- nf-fa-google
      ["microsoft.com"] = { "\u{f0372}", color = "#00a4ef" }, -- nf-md-microsoft
      ["wikipedia.org"] = "\u{f266}", -- nf-fa-wikipedia_w
      ["spotify.com"] = { "\u{f1bc}", color = "#1db954" }, -- nf-fa-spotify
      ["twitch.tv"] = { "\u{f1e8}", color = "#9146ff" }, -- nf-fa-twitch
      ["gitlab.com"] = { "\u{f296}", color = "#fc6d26" }, -- nf-fa-gitlab
      ["steampowered.com"] = "\u{f1b6}", -- nf-fa-steam
      ["amazon.com"] = { "\u{f270}", color = "#ff9900" }, -- nf-fa-amazon
      ["dev.to"] = "\u{f0d6e}", -- nf-md-dev_to
      ["pinterest.com"] = { "\u{f0d2}", color = "#e60023" }, -- nf-fa-pinterest
      ["vimeo.com"] = { "\u{f27d}", color = "#1ab7ea" }, -- nf-fa-vimeo
      ["producthunt.com"] = { "\u{f288}", color = "#da552f" }, -- nf-fa-product_hunt
      ["discord.com"] = { "\u{f066f}", color = "#5865f2" }, -- nf-md-discord
      ["playstation.com"] = { "\u{e230}", color = "#2e6db4" }, -- nf-fae-playstation
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
    dashboard = {
      open = "<CR>",
      timeline = "t",
      unread = "u",
      starred = "s",
      category = "c",
      refresh = "r",
      close = "q",
      help = "?",
    },
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
