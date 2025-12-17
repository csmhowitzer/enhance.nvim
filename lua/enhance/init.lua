-- enhance.nvim - Database UI enhancement for Neovim
-- Main module entry point

local M = {}

---@class EnhanceConfig
---@field enabled boolean Enable the plugin
---@field connections table[] List of database connections
---@field keymaps table Keymap configuration
---@field ui table UI configuration
---@field status_line table Status line configuration

---@type EnhanceConfig
local default_config = {
  enabled = true,
  connections = {},
  keymaps = {
    execute_query = "<F5>",
    save_query = ":w",
  },
  ui = {
    results_position = "split", -- "split", "vsplit", "tab"
    show_query_time = true,
  },
  status_line = {
    enabled = true,
    position = "top",  -- 'top' | 'bottom' | 'none'
    highlight = "EnhanceStatusLine",
  },
}

---@type EnhanceConfig
M.config = {}

---Setup enhance.nvim with user configuration
---@param opts EnhanceConfig? User configuration options
function M.setup(opts)
  -- Merge user config with defaults
  M.config = vim.tbl_deep_extend("force", default_config, opts or {})

  if not M.config.enabled then
    return
  end

  -- Set up default highlight group for status line
  vim.api.nvim_set_hl(0, 'EnhanceStatusLine', {
    fg = '#89b4fa',  -- Light blue
    bold = true,
    default = true  -- Allow user to override
  })

  -- Initialize modules
  require("enhance.connections").setup(M.config.connections)

  -- Create user commands
  vim.api.nvim_create_user_command("EnhanceToggle", function()
    M.toggle()
  end, { desc = "Toggle enhance.nvim" })

  vim.api.nvim_create_user_command("EnhanceStart", function()
    require("enhance.explorer").start()
  end, { desc = "Start enhance workspace" })

  vim.api.nvim_create_user_command("EnhanceExplorer", function()
    require("enhance.explorer").toggle()
  end, { desc = "Toggle database explorer" })

  vim.api.nvim_create_user_command("EnhanceResults", function()
    require("enhance.explorer").toggle_results()
  end, { desc = "Toggle results window" })

  vim.api.nvim_create_user_command("EnhanceQuery", function()
    require("enhance.explorer").new_query()
  end, { desc = "Create new query" })

  vim.api.nvim_create_user_command("EnhanceDeleteFile", function(opts)
    require("enhance.explorer").delete_file(opts.args)
  end, { nargs = "?", desc = "Delete file (current buffer or specified filename)" })

  vim.api.nvim_create_user_command("EnhanceStop", function()
    require("enhance.explorer").stop()
  end, { desc = "Stop enhance workspace" })

  -- Set up global keymaps
  -- Smart keymap: starts workspace if not initialized, otherwise toggles explorer
  vim.keymap.set('n', '<leader>de', function()
    local explorer = require("enhance.explorer")
    if explorer.is_initialized() then
      explorer.toggle()
    else
      explorer.start()
    end
  end, { desc = "Toggle [D]atabase [E]xplorer" })

  -- Toggle results window
  vim.keymap.set('n', '<leader>dr', function()
    require("enhance.explorer").toggle_results()
  end, { desc = "Toggle [D]atabase [R]esults" })

  -- Create new query
  vim.keymap.set('n', '<leader>dq', function()
    require("enhance.explorer").new_query()
  end, { desc = "New [D]atabase [Q]uery" })

  -- Delete current file
  vim.keymap.set('n', '<leader>dd', function()
    require("enhance.explorer").delete_file()
  end, { desc = "[D]elete [D]atabase file" })
end

---Toggle plugin enabled state
function M.toggle()
  M.config.enabled = not M.config.enabled
  local status = M.config.enabled and "enabled" or "disabled"
  vim.notify("enhance.nvim " .. status, vim.log.levels.INFO)
end

---Get current configuration
---@return EnhanceConfig
function M.get_config()
  return M.config
end

-- Expose for testing
M._default_config = default_config

return M

