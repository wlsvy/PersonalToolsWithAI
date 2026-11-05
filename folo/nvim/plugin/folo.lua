if vim.g.loaded_folo then
  return
end
vim.g.loaded_folo = true

vim.api.nvim_create_user_command("Folo", function()
  require("folo.ui").timeline({}, "all")
end, { desc = "folo: timeline" })

vim.api.nvim_create_user_command("FoloUnread", function()
  require("folo.ui").timeline({ unread = true }, "unread")
end, { desc = "folo: unread entries" })
