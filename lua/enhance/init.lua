-- enhance.nvim - Database UI enhancement for Neovim
-- Main module entry point

local M = {}

---@class EnhanceConfig
---@field enabled boolean Enable the plugin
---@field connections_file string Path to connections JSON file (vim-dadbod-ui format)
---@field keymaps table Keymap configuration
---@field ui table UI configuration
---@field status_line table Status line configuration

---@type EnhanceConfig
local default_config = {
  enabled = true,
  connections = {},  -- For backward compatibility with tests
  connections_file = vim.fn.expand("~/.local/share/enhance/connections.json"),
  format_results = true,  -- Enable consistent result formatting (parser + formatter)
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
    highlights = {
      label = "EnhanceStatusLabel",
      value = "EnhanceStatusValue",
      connection = "EnhanceStatusConnection",
      db_type = "EnhanceStatusDBType",
      timestamp = "EnhanceStatusTimestamp",
      separator = "EnhanceStatusSeparator",
      line_number = "EnhanceLineNumber",
      line_number_accent = "EnhanceLineNumberAccent",
    },
  },
}

---@type EnhanceConfig
M.config = {}

---Setup highlight groups for status line
---Can be called multiple times to refresh highlights (e.g., after colorscheme change)
function M.setup_highlights()
  -- Set up default highlight groups for status line
  -- Colors from scratch-manager.nvim and augment.nvim for consistency
  vim.api.nvim_set_hl(0, 'EnhanceStatusLabel', {
    fg = '#89b4fa',  -- Light blue (scratch-manager border/separator)
    bold = true,
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceStatusValue', {
    fg = '#a6d189',  -- Green (scratch-manager header)
    bold = true,
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceStatusConnection', {
    fg = '#74c7ec',  -- Cyan/Teal (scratch-manager title/footer)
    bold = true,
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceStatusDBType', {
    fg = '#cba6f7',  -- Purple (augment chat border)
    bold = true,
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceStatusTimestamp', {
    fg = '#f9e2af',  -- Yellow (different from DB type)
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceStatusSeparator', {
    fg = '#6c7086',  -- Gray (subtle separator)
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceLineNumber', {
    fg = '#6c7086',  -- Gray (subtle, not distracting)
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceLineNumberAccent', {
    fg = '#cba6f7',  -- Purple (augment purple for every 5th line)
    bold = true,
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceCursorLine', {
    bg = '#313244',  -- Gray background (matches catppuccin mocha default)
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceCursorLineAccent', {
    bg = '#3f3144',  -- Purple-tinted background for every 5th line
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceNull', {
    fg = '#f9e2af',  -- Yellow (same as timestamp)
    italic = true,
    default = true
  })
end

---Setup enhance.nvim with user configuration
---@param opts EnhanceConfig? User configuration options
function M.setup(opts)
  -- Merge user config with defaults
  M.config = vim.tbl_deep_extend("force", default_config, opts or {})

  if not M.config.enabled then
    return
  end

  -- Setup highlights
  M.setup_highlights()

  -- Re-apply highlights on colorscheme change (following scratch-manager pattern)
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("EnhanceHighlights", { clear = true }),
    callback = function()
      M.setup_highlights()
    end,
  })

  -- Initialize modules - load connections from file
  require("enhance.connections").setup(M.config.connections_file)

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

  vim.api.nvim_create_user_command("EnhanceRefresh", function()
    require("enhance.explorer").refresh()
  end, { desc = "Refresh explorer (clear cache and redraw)" })

  vim.api.nvim_create_user_command("EnhanceQuery", function()
    require("enhance.explorer").new_query()
  end, { desc = "Create new query" })

  vim.api.nvim_create_user_command("EnhanceDeleteFile", function(opts)
    require("enhance.explorer").delete_file(opts.args)
  end, { nargs = "?", desc = "Delete file (current buffer or specified filename)" })

  vim.api.nvim_create_user_command("EnhanceStop", function()
    require("enhance.explorer").stop()
  end, { desc = "Stop enhance workspace" })

  vim.api.nvim_create_user_command("EnhanceToggleFormatting", function()
    require("enhance.config").toggle_formatting()
  end, { desc = "Toggle result formatting (parser + formatter)" })

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

