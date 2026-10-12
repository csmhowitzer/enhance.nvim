-- lazy.nvim discovers this file automatically; no user build setting is needed.
-- Load by filename because lazy.nvim need not have put the plugin on runtimepath.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h')
local installer = dofile(root .. '/lua/enhance/helper_install.lua')
local manifest = installer.manifest()
if manifest.release == false then
  vim.notify('Enhance: helper packaging is staged; no helper release has been published yet', vim.log.levels.INFO)
  return
end
local path, err = installer.install()
if not path then error('Enhance helper installation failed: ' .. tostring(err)) end
vim.notify('Enhance helper verified: ' .. path, vim.log.levels.INFO)
