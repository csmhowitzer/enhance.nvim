-- Minimal init for testing enhance.nvim

-- Add plugin to runtimepath
vim.opt.rtp:append(".")

-- Add plenary to runtimepath (assuming it's installed via lazy.nvim)
vim.opt.rtp:append("~/.local/share/nvim/lazy/plenary.nvim")

-- Set up basic Neovim options for testing
vim.opt.swapfile = false
vim.opt.hidden = true

-- Load the plugin
require("enhance").setup({
  enabled = true,
  connections = {
    {
      name = "Test SQLite",
      type = "sqlite",
      path = "~/.local/share/nvim/dadbod_ui/example.db",
    }
  },
})

