-- Minimal init for testing enhance.nvim
-- Works with `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests"`.

local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

-- Plenary runs every spec in a child nvim. Without a minimal_init option those children would load the
-- user's full config, so point them back at this file via $VIMINIT (used when no -u is given).
vim.env.VIMINIT = "luafile " .. vim.fn.fnameescape(plugin_dir .. "/tests/minimal_init.lua")

-- Find plugins before redirecting XDG dirs below; children inherit LAZY_DIR
vim.env.LAZY_DIR = vim.env.LAZY_DIR or (vim.fn.stdpath("data") .. "/lazy")

-- Keep test artifacts (query files, pins, connection folders, helper cache lookups) out of the user's
-- real data, cache and state dirs. stdpath() is fixed at startup, so this applies to the per-spec child
-- processes, which inherit the env.
if not vim.env.ENHANCE_TEST_HOME then
  vim.env.ENHANCE_TEST_HOME = vim.fn.tempname()
  vim.env.XDG_CACHE_HOME = vim.env.ENHANCE_TEST_HOME .. "/cache"
  vim.env.XDG_DATA_HOME = vim.env.ENHANCE_TEST_HOME .. "/data"
  vim.env.XDG_STATE_HOME = vim.env.ENHANCE_TEST_HOME .. "/state"
  -- Create the shared dirs once, here, so parallel spec processes don't race on them
  for _, dir in ipairs({ "/cache", "/data/enhance.nvim", "/state" }) do
    vim.fn.mkdir(vim.env.ENHANCE_TEST_HOME .. dir, "p")
  end
end

-- Keep the user's own config (plugin/, after/plugin/) out of the test processes
local config_dir = vim.fn.stdpath("config")
vim.opt.rtp:remove(config_dir)
vim.opt.rtp:remove(config_dir .. "/after")

-- The plugin and its test dependency (installed via lazy.nvim)
local plenary = vim.env.LAZY_DIR .. "/plenary.nvim"
if vim.fn.isdirectory(plenary) == 0 then
  error("plenary.nvim is required for testing (looked in " .. vim.env.LAZY_DIR .. "; set $LAZY_DIR to override)")
end
vim.opt.rtp:prepend(plugin_dir)
vim.opt.rtp:append(plenary)
vim.cmd("runtime plugin/plenary.vim")

-- Set up basic Neovim options for testing
vim.opt.swapfile = false
vim.opt.hidden = true

-- Load the plugin
require("enhance").setup({
  enabled = true,
  connections_file = {
    {
      name = "Test SQLite",
      type = "sqlite",
      path = ":memory:",
    }
  },
})
