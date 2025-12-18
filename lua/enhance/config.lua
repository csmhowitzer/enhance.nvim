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

---@class StatusLineHighlights
---@field label string Highlight group for labels (default: 'EnhanceStatusLabel')
---@field value string Highlight group for values (default: 'EnhanceStatusValue')
---@field connection string Highlight group for connection name (default: 'EnhanceStatusConnection')
---@field db_type string Highlight group for database type (default: 'EnhanceStatusDBType')
---@field timestamp string Highlight group for timestamp (default: 'EnhanceStatusTimestamp')
---@field separator string Highlight group for separator line (default: 'EnhanceStatusSeparator')
---@field line_number string Highlight group for line numbers (default: 'EnhanceLineNumber')
---@field line_number_accent string Highlight group for every 5th line number (default: 'EnhanceLineNumberAccent')

---@class StatusLineConfig
---@field enabled boolean Enable status line display (default: true)
---@field position string Position of status line: 'top' | 'bottom' | 'none' (default: 'top')
---@field highlights StatusLineHighlights Highlight groups for different parts of status line

---Get default configuration
---@return table Default configuration
function M.defaults()
  return {
    enabled = true,
    connections_file = vim.fn.expand("~/.local/share/enhance/connections.json"),
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

---Parse SQLite URL
---@param url string SQLite URL (e.g., "sqlite:/path/to/db" or "sqlite:///path/to/db")
---@return table? connection Parsed connection or nil
---@return string? error Error message if failed
local function parse_sqlite_url(url)
  -- SQLite format: sqlite:/path or sqlite:///path
  local path = url:match("^sqlite:(.+)$")
  if not path then
    return nil, "Invalid SQLite URL format"
  end

  -- Remove leading slashes if present (sqlite:/// -> /path)
  path = path:gsub("^//", "")

  return {
    type = "sqlite",
    path = path,
  }, nil
end

---Parse SQL Server URL
---@param url string SQL Server URL (e.g., "sqlserver://host/db;user=x;password=y;TrustServerCertificate=yes;")
---@return table? connection Parsed connection or nil
---@return string? error Error message if failed
local function parse_sqlserver_url(url)
  -- SQL Server format: sqlserver://host/database;param=value;param=value;
  local host, database, params = url:match("^sqlserver://([^/]+)/([^;]+);?(.*)$")
  if not host or not database then
    return nil, "Invalid SQL Server URL format"
  end

  local conn = {
    type = "sqlserver",
    server = host,
    database = database,
  }

  -- Parse semicolon-separated parameters
  if params and params ~= "" then
    for param in params:gmatch("([^;]+)") do
      local key, value = param:match("^([^=]+)=(.+)$")
      if key and value then
        key = key:lower()
        if key == "user" then
          conn.user = value
        elseif key == "password" then
          conn.password = value
        elseif key == "trustservercertificate" then
          conn.trust_server_certificate = (value:lower() == "yes" or value:lower() == "true")
        end
      end
    end
  end

  return conn, nil
end

---Parse MySQL URL
---@param url string MySQL URL (e.g., "mysql://user:password@host:port/database")
---@return table? connection Parsed connection or nil
---@return string? error Error message if failed
local function parse_mysql_url(url)
  -- MySQL format: mysql://[user[:password]@]host[:port]/database
  local user, password, host, port, database = url:match("^mysql://([^:]+):([^@]+)@([^:/]+):?([^/]*)/(.+)$")

  if not user or not host or not database then
    return nil, "Invalid MySQL URL format"
  end

  return {
    type = "mysql",
    host = host,
    port = port ~= "" and tonumber(port) or 3306,
    database = database,
    user = user,
    password = password,
  }, nil
end

---Parse PostgreSQL URL
---@param url string PostgreSQL URL (e.g., "postgresql://user:password@host:port/database")
---@return table? connection Parsed connection or nil
---@return string? error Error message if failed
local function parse_postgres_url(url)
  -- PostgreSQL format: postgresql://[user[:password]@]host[:port]/database or postgres://...
  local protocol, user, password, host, port, database = url:match("^(postgres[ql]*)://([^:]+):([^@]+)@([^:/]+):?([^/]*)/(.+)$")

  if not user or not host or not database then
    return nil, "Invalid PostgreSQL URL format"
  end

  return {
    type = "postgres",
    host = host,
    port = port ~= "" and tonumber(port) or 5432,
    database = database,
    user = user,
    password = password,
  }, nil
end

---Parse database connection URL
---@param url string Database connection URL
---@return table? connection Parsed connection or nil
---@return string? error Error message if failed
local function parse_connection_url(url)
  if url:match("^sqlite:") then
    return parse_sqlite_url(url)
  elseif url:match("^sqlserver:") then
    return parse_sqlserver_url(url)
  elseif url:match("^mysql:") then
    return parse_mysql_url(url)
  elseif url:match("^postgres") then
    return parse_postgres_url(url)
  else
    return nil, "Unknown database URL protocol"
  end
end

---Load connections from JSON file (vim-dadbod-ui format)
---@param filepath string Path to connections JSON file
---@return table[] connections List of connections
---@return string? error Error message if failed
function M.load_connections(filepath)
  -- Expand path
  local expanded_path = vim.fn.expand(filepath)

  -- Check if file exists
  if vim.fn.filereadable(expanded_path) ~= 1 then
    return {}, "Connections file not found: " .. expanded_path
  end

  -- Read file
  local file = io.open(expanded_path, "r")
  if not file then
    return {}, "Failed to open connections file: " .. expanded_path
  end

  local content = file:read("*all")
  file:close()

  -- Parse JSON
  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return {}, "Failed to parse connections JSON: " .. tostring(data)
  end

  -- Validate structure - expect array of {name, url}
  if type(data) ~= "table" then
    return {}, "Invalid connections file format: expected JSON array"
  end

  -- Parse each connection URL
  local connections = {}
  for i, entry in ipairs(data) do
    if not entry.name or not entry.url then
      return {}, string.format("Connection #%d: missing 'name' or 'url' field", i)
    end

    -- Parse the URL
    local conn, err = parse_connection_url(entry.url)
    if err then
      return {}, string.format("Connection #%d (%s): %s", i, entry.name, err)
    end

    -- Add the name
    conn.name = entry.name

    -- Validate the parsed connection
    local valid, validate_err = M.validate_connection(conn)
    if not valid then
      return {}, string.format("Connection #%d (%s): %s", i, entry.name, validate_err)
    end

    table.insert(connections, conn)
  end

  return connections, nil
end

---Validate full configuration
---@param config table Configuration to validate
---@return boolean valid True if valid
---@return string? error Error message if invalid
function M.validate_config(config)
  -- connections = {} is no longer supported
  if config.connections then
    return false, "connections = {} is no longer supported. Please use connections_file with vim-dadbod-ui format. See :help enhance-connections"
  end

  -- Validate connections_file if provided
  if config.connections_file then
    local filepath = vim.fn.expand(config.connections_file)
    if vim.fn.filereadable(filepath) ~= 1 then
      -- File doesn't exist yet - that's okay, we'll create it
      -- But warn the user
      vim.notify(
        string.format("Connections file not found: %s\nCreate this file with your database connections in vim-dadbod-ui format.", filepath),
        vim.log.levels.WARN
      )
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
M._load_connections = M.load_connections
M._parse_sqlite_url = parse_sqlite_url
M._parse_sqlserver_url = parse_sqlserver_url
M._parse_mysql_url = parse_mysql_url
M._parse_postgres_url = parse_postgres_url
M._parse_connection_url = parse_connection_url

return M

