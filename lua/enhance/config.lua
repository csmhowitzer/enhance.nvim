-- enhance.nvim - Configuration management
-- Handles configuration validation and defaults

local M = {}

---@class ConnectionConfig
---@field name string Connection display name
---@field type string Database type (sqlite, sqlserver, mysql, postgres)
---@field path string? Path to database file (for sqlite)
---@field host string? Database host (mysql, postgres, sqlserver)
---@field server string? Database server (sqlserver - preferred over host)
---@field port number? Database port
---@field database string? Database name
---@field user string? Username
---@field username string? Username (alternative)
---@field password string? Password
---@field trust_server_certificate boolean? Trust server certificate for SQL Server (default: true)

---@class StatusLineConfig
---@field enabled boolean Enable status line display (default: true)
---@field position string Position of status line: 'top' | 'bottom' | 'none' (default: 'top')
---@field highlight string Highlight group name for status line (default: 'EnhanceStatusLine')

---Get default configuration
---@return table Default configuration
function M.defaults()
  return {
    enabled = true,
    connections = {},
    keymaps = {
      execute_query = "<F5>",
      save_query = ":w",
    },
    ui = {
      results_position = "split",
      show_query_time = true,
    },
    status_line = {
      enabled = true,
      position = "top",  -- 'top' | 'bottom' | 'none'
      highlight = "EnhanceStatusLine",
    },
  }
end

---Validate connection configuration
---@param conn ConnectionConfig Connection to validate
---@return boolean valid True if valid
---@return string? error Error message if invalid
function M.validate_connection(conn)
  if not conn.name or conn.name == "" then
    return false, "Connection name is required"
  end
  
  if not conn.type or conn.type == "" then
    return false, "Connection type is required"
  end
  
  -- Type-specific validation
  local db_type = conn.type:lower():gsub("[%s%-_]", "")

  if db_type == "sqlite" then
    if not conn.path or conn.path == "" then
      return false, "SQLite connection requires 'path'"
    end
  elseif db_type == "sqlserver" or db_type == "mssql" then
    if not conn.server and not conn.host then
      return false, "SQL Server connection requires 'server' or 'host'"
    end
    if not conn.database then
      return false, "SQL Server connection requires 'database'"
    end
  elseif db_type == "mysql" or db_type == "mariadb" then
    if not conn.host then
      return false, "MySQL connection requires 'host'"
    end
    if not conn.database then
      return false, "MySQL connection requires 'database'"
    end
  elseif db_type == "postgres" or db_type == "postgresql" then
    if not conn.host then
      return false, "PostgreSQL connection requires 'host'"
    end
    if not conn.database then
      return false, "PostgreSQL connection requires 'database'"
    end
  end
  
  return true, nil
end

---Validate full configuration
---@param config table Configuration to validate
---@return boolean valid True if valid
---@return string? error Error message if invalid
function M.validate_config(config)
  if config.connections then
    for i, conn in ipairs(config.connections) do
      local valid, err = M.validate_connection(conn)
      if not valid then
        return false, string.format("Connection #%d: %s", i, err)
      end
    end
  end
  
  return true, nil
end

---Merge user configuration with defaults
---@param user_config table? User configuration
---@return table Merged configuration
function M.merge(user_config)
  local defaults = M.defaults()
  return vim.tbl_deep_extend("force", defaults, user_config or {})
end

-- Expose for testing
M._validate_connection = M.validate_connection
M._validate_config = M.validate_config

return M

