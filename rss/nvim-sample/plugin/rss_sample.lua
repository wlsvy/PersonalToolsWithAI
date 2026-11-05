if vim.g.loaded_rss_sample then
  return
end
vim.g.loaded_rss_sample = true

local function ui()
  return require("rss_sample.ui")
end

vim.api.nvim_create_user_command("RssSample", function()
  ui().feeds()
end, { desc = "rss_sample: feeds" })

vim.api.nvim_create_user_command("RssSampleUnread", function()
  ui().entries({ unread = true }, "unread")
end, { desc = "rss_sample: unread entries" })

vim.api.nvim_create_user_command("RssSampleAdd", function(o)
  ui().add(o.args)
end, { nargs = 1, desc = "rss_sample: add feed by url" })

vim.api.nvim_create_user_command("RssSampleRefresh", function(o)
  ui().refresh(o.args ~= "" and tonumber(o.args) or nil)
end, { nargs = "?", desc = "rss_sample: refresh one feed (id) or all" })
