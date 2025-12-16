-- enhance.nvim - Plugin initialization
-- Entry point for the plugin

-- Prevent loading twice
if vim.g.loaded_enhance then
  return
end
vim.g.loaded_enhance = true

-- Plugin will be initialized via setup() call in user config
-- No automatic initialization to allow user configuration

