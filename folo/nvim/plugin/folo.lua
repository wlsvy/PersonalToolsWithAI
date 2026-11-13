if vim.g.loaded_folo then
  return
end
vim.g.loaded_folo = true

vim.api.nvim_create_user_command("Folo", function()
  require("folo.ui").dashboard()
end, { desc = "folo: dashboard" })

vim.api.nvim_create_user_command("FoloUnread", function()
  require("folo.ui").timeline({ unread = true }, "unread")
end, { desc = "folo: unread entries" })

vim.api.nvim_create_user_command("FoloCategory", function(o)
  if o.args ~= "" then
    require("folo.ui").category(o.args)
  else
    require("folo.ui").pick_category()
  end
end, { nargs = "?", desc = "folo: entries in a category (no argument: pick from list)" })

vim.api.nvim_create_user_command("FoloStarred", function()
  require("folo.ui").starred()
end, { desc = "folo: collected entries" })
