if vim.g.loaded_rss then
  return
end
vim.g.loaded_rss = true

local function ui()
  return require("rss.ui")
end

vim.api.nvim_create_user_command("Rss", function()
  ui().feeds()
end, { desc = "rss: feeds" })

vim.api.nvim_create_user_command("RssUnread", function()
  ui().entries({ unread = true }, "unread")
end, { desc = "rss: unread entries" })

vim.api.nvim_create_user_command("RssAdd", function(o)
  ui().add(o.args)
end, { nargs = 1, desc = "rss: add feed by url" })

vim.api.nvim_create_user_command("RssRefresh", function(o)
  ui().refresh(o.args ~= "" and tonumber(o.args) or nil)
end, { nargs = "?", desc = "rss: refresh one feed (id) or all" })
