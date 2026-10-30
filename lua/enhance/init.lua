-- enhance.nvim - Database UI enhancement for Neovim
-- Main module entry point

local M = {}

---@class EnhanceConfig
---@field enabled boolean Enable the plugin
---@field connections_file string Path to connections JSON file (vim-dadbod-ui format)
---@field keymaps table Keymap configuration
---@field ui table UI configuration
---@field ui.dashboard table? Dashboard appearance (card_border: highlight group)
---@field status_line table Status line configuration

---@type EnhanceConfig
local default_config = require('enhance.config').defaults()

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

  vim.api.nvim_set_hl(0, 'EnhanceJsonCell', {
    fg = '#74c7ec',  -- Cyan (scratch-manager title/footer)
    italic = true,
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceNumberCell', {
    fg = '#fab387',  -- Peach (Catppuccin Mocha)
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceDateCell', {
    fg = '#cba6f7',  -- Mauve (Catppuccin Mocha)
    default = true
  })

  -- JSON viewer floating window highlights
  vim.api.nvim_set_hl(0, 'EnhanceJsonBorder', {
    fg = '#f9e2af',  -- Yellow (catppuccin mocha yellow)
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceJsonTitle', {
    fg = '#a6d189',  -- Green (catppuccin mocha green)
    bold = true,
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceJsonFooter', {
    fg = '#74c7ec',  -- Cyan (same as JSON cell highlight)
    italic = true,
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceError', {
    fg = '#f38ba8',  -- Red (catppuccin mocha red)
    bold = true,
    default = true
  })

  -- Explorer tree node highlight groups
  vim.api.nvim_set_hl(0, 'EnhanceIconYellow', {
    fg = '#f9e2af',  -- Yellow (catppuccin mocha yellow) - Level 0: DB connection icons
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceDashboardBorder', {
    fg = '#cba6f7', -- Purple database card borders
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceDashboardTableBorder', {
    fg = '#a6e3a1', -- Green table card borders
    default = true
  })
  vim.api.nvim_set_hl(0, 'EnhanceDashboardCategory', {
    fg = '#cba6f7', bold = true, default = true
  })
  vim.api.nvim_set_hl(0, 'EnhanceDashboardLabel', {
    fg = '#89b4fa', bold = true, default = true
  })
  vim.api.nvim_set_hl(0, 'EnhanceDashboardHint', {
    fg = '#89b4fa', italic = true, default = true
  })
  local subtitle = vim.api.nvim_get_hl(0, { name = 'Comment' })
  vim.api.nvim_set_hl(0, 'EnhanceDashboardMetaDescription', {
    fg = subtitle.fg or '#6c7086', italic = true, default = true
  })
  vim.api.nvim_set_hl(0, 'EnhanceDashboardReferenceSelected', {
    bg = '#313244', default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceIconBlue', {
    fg = '#89b4fa',  -- Blue - Level 1: category folders (Tables, Views, Buffers, etc.)
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceIconCyan', {
    fg = '#74c7ec',  -- Cyan (same as JSON cell) - Level 2: individual items
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceIconOrange', {
    fg = '#fab387',  -- Orange - Level 3: actions + buffers with results
    default = true
  })

  vim.api.nvim_set_hl(0, 'EnhanceIconPurple', {
    fg = '#cba6f7',  -- Purple - result buffers
    default = true
  })
end

---Setup enhance.nvim with user configuration
---@param opts EnhanceConfig? User configuration options
function M.setup(opts)
  -- Merge user config with defaults
  if opts ~= nil and type(opts) ~= 'table' then error('Enhance setup options must be a table', 2) end
  local config = require('enhance.config')
  local candidate = config.merge(opts)
  local valid, err = config.validate_config(candidate)
  if not valid then error('Invalid Enhance configuration: ' .. err, 2) end
  M.config = candidate

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

  vim.api.nvim_create_user_command("EnhanceDisconnect", function()
    require("enhance.connections").disconnect()
  end, { desc = "Disconnect from current database" })

  M.setup_keymaps()
end

---Key under the configured prefix (keymaps.prefix, default <leader>o), or nil when prefixed keys are off
---@param suffix string
---@return string|nil
function M.prefixed(suffix)
  -- Before setup() (e.g. modules used directly), fall back to the default prefix
  local keymaps = M.config.keymaps or require("enhance.config").defaults().keymaps
  local prefix = keymaps.prefix
  if not prefix or prefix == "" then
    return nil
  end
  return prefix .. suffix
end

---Delete the current query file after one yes/no prompt that names it. Only Enhance query files (tmp or
---saved, in Enhance's storage) can be deleted; any other buffer is refused.
function M.confirm_delete_file()
  local explorer = require("enhance.explorer")
  local path = explorer.current_query_file()
  if not path then
    vim.notify("Not an Enhance query file", vim.log.levels.WARN)
    return
  end
  if vim.fn.confirm("Delete " .. vim.fn.fnamemodify(path, ":t") .. "?", "&Yes\n&No", 2) == 1 then
    explorer.delete_confirmed(path)
  end
end

---Global keys under keymaps.prefix (default <leader>o)
function M.setup_keymaps()
  local function map(suffix, fn, desc)
    local lhs = M.prefixed(suffix)
    if lhs then
      vim.keymap.set("n", lhs, fn, { desc = desc })
    end
  end
  local prefix = M.prefixed("")
  if prefix then
    local ok, wk = pcall(require, "which-key")
    if ok and wk.add then
      wk.add({ { prefix, group = "enhance (database)" } })
    end
  end

  -- Smart key: starts the workspace if not initialized, otherwise toggles the explorer
  map("e", function()
    local explorer = require("enhance.explorer")
    if explorer.is_initialized() then
      explorer.toggle()
    else
      explorer.start()
    end
  end, "Database [E]xplorer")
  map("q", function()
    require("enhance.explorer").new_query()
  end, "New [Q]uery")
  map("r", function()
    require("enhance.explorer").toggle_results()
  end, "Toggle [R]esults")
  map("j", function()
    require("enhance.json_viewer").show()
  end, "Display [J]SON field")
  map("h", function()
    require("enhance.results").toggle_datatypes()
  end, "Toggle type [H]eaders")
  map("x", function()
    require("enhance.connections").disconnect()
  end, "Disconnect (e[X]it)")
  map("d", M.confirm_delete_file, "[D]elete query file (asks first)")
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
