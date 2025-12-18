-- enhance.nvim - Health check
-- Provides :checkhealth enhance diagnostics

local M = {}

---Check if a command is available
---@param cmd string Command name
---@return boolean available True if command exists
local function check_command(cmd)
  return vim.fn.executable(cmd) == 1
end

---Main health check function
function M.check()
  vim.health.start("enhance.nvim")

  -- Check plugin loaded
  local ok, enhance = pcall(require, "enhance")
  if ok then
    vim.health.ok("Plugin loaded successfully")
  else
    vim.health.error("Plugin failed to load: " .. tostring(enhance))
    return
  end

  -- Check configuration
  local config = enhance.get_config()
  if config.enabled then
    vim.health.ok("Plugin is enabled")
  else
    vim.health.warn("Plugin is disabled")
  end

  -- Check plugin dependencies
  vim.health.start("Plugin Dependencies")

  -- Check vim-dadbod (required)
  if vim.fn.exists(':DB') == 2 then
    vim.health.ok("vim-dadbod is installed")
  else
    vim.health.error("vim-dadbod is required but not found", {
      "Install vim-dadbod: https://github.com/tpope/vim-dadbod",
      "Add to your plugin manager:",
      '  { "tpope/vim-dadbod" }',
    })
  end

  -- Check vim-dadbod-completion (recommended)
  if vim.fn.exists('*vim_dadbod_completion#omni#complete') == 1 then
    vim.health.ok("vim-dadbod-completion is installed")
  else
    vim.health.warn("vim-dadbod-completion is recommended for SQL completions", {
      "Install vim-dadbod-completion: https://github.com/kristijanhusak/vim-dadbod-completion",
      "Add to your plugin manager:",
      '  { "kristijanhusak/vim-dadbod-completion" }',
    })
  end

  -- Check database CLI tools
  vim.health.start("Database CLI Tools")

  if check_command("sqlite3") then
    vim.health.ok("sqlite3 found: " .. vim.fn.exepath("sqlite3"))
  else
    vim.health.warn("sqlite3 not found - SQLite support unavailable", {
      "Install: brew install sqlite3 (macOS) or apt install sqlite3 (Linux)",
    })
  end

  if check_command("sqlcmd") then
    vim.health.ok("sqlcmd found: " .. vim.fn.exepath("sqlcmd"))
  else
    vim.health.info("sqlcmd not found - SQL Server support unavailable", {
      "Install: brew install sqlcmd (macOS) or see Microsoft docs for Windows/Linux",
    })
  end

  if check_command("mysql") then
    vim.health.ok("mysql found: " .. vim.fn.exepath("mysql"))
  else
    vim.health.info("mysql not found - MySQL support unavailable", {
      "Install: brew install mysql-client (macOS) or apt install mysql-client (Linux)",
    })
  end

  if check_command("psql") then
    vim.health.ok("psql found: " .. vim.fn.exepath("psql"))
  else
    vim.health.info("psql not found - PostgreSQL support unavailable", {
      "Install: brew install postgresql (macOS) or apt install postgresql-client (Linux)",
    })
  end
  
  -- Check connections
  vim.health.start("Connections")
  
  local connections = require("enhance.connections").get_connections()
  if #connections > 0 then
    vim.health.ok(string.format("%d connection(s) configured", #connections))
    for _, conn in ipairs(connections) do
      vim.health.info(string.format("  - %s (%s)", conn.name, conn.type))
      
      -- Validate SQLite database files
      if conn.type == "sqlite" and conn.path then
        local db_path = vim.fn.expand(conn.path)
        if vim.fn.filereadable(db_path) == 1 then
          vim.health.ok(string.format("    Database file exists: %s", db_path))
        else
          vim.health.error(string.format("    Database file not found: %s", db_path))
        end
      end
    end
  else
    vim.health.warn("No connections configured")
  end
  
  -- Check current connection
  local current = require("enhance.connections").get_current()
  if current then
    vim.health.ok("Active connection: " .. current.name)
  else
    vim.health.info("No active connection")
  end
  
  -- Check commands
  vim.health.start("Commands")
  
  local commands = {
    "EnhanceToggle",
    "EnhanceConnect",
  }
  
  for _, cmd in ipairs(commands) do
    if vim.fn.exists(":" .. cmd) == 2 then
      vim.health.ok(":" .. cmd .. " available")
    else
      vim.health.error(":" .. cmd .. " not found")
    end
  end
end

return M

