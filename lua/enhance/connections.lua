-- enhance.nvim - Connection management
-- Handles database connections and connection browser

local M = {}

---@type table[]
local connections = {}

---@type table?
local current_connection = nil

---Setup connections from JSON file or array (for testing)
---@param connections_file_or_array string|table[]|nil Path to connections JSON file or array of connections
function M.setup(connections_file_or_array)
  -- Handle nil or empty table - add default connection
  if connections_file_or_array == nil or (type(connections_file_or_array) == "table" and #connections_file_or_array == 0) then
    connections = {
      {
        name = "Test SQLite",
        type = "sqlite",
        path = vim.fn.expand("~/.local/share/enhance/test.db"),
      }
    }
    return
  end

  -- Handle direct connection array (for testing)
  if type(connections_file_or_array) == "table" then
    connections = connections_file_or_array
    return
  end

  -- Load connections from file
  local config = require("enhance.config")
  local loaded_connections, err = config.load_connections(connections_file_or_array)

  if err then
    vim.notify("Failed to load connections: " .. err, vim.log.levels.ERROR)
    connections = {}
    return
  end

  connections = loaded_connections

  if #connections == 0 then
    vim.notify("No connections found in " .. connections_file_or_array, vim.log.levels.WARN)
  else
    vim.notify(string.format("Loaded %d connection(s) from %s", #connections, connections_file_or_array), vim.log.levels.INFO)
  end
end

---Get all connections
---@return table[] List of connections
function M.get_connections()
  return connections
end

---Get connection by name
---@param name string Connection name
---@return table? Connection or nil if not found
function M.get_connection(name)
  for _, conn in ipairs(connections) do
    if conn.name == name then
      return conn
    end
  end
  return nil
end

---Set current active connection
---@param conn table Connection to set as active
function M.set_current(conn)
  current_connection = conn
  vim.notify("Connected to: " .. conn.name, vim.log.levels.INFO)
end

---Get current active connection
---@return table? Current connection or nil
function M.get_current()
  return current_connection
end

---Disconnect from current connection
function M.disconnect()
  if not current_connection then
    vim.notify("No active connection to disconnect", vim.log.levels.WARN)
    return
  end

  local conn_name = current_connection.name
  current_connection = nil
  vim.notify("Disconnected from: " .. conn_name, vim.log.levels.INFO)

  -- Collapse tree and refresh explorer if it exists
  local explorer = require("enhance.explorer")
  if explorer.is_initialized() then
    explorer.collapse_connection(conn_name)
    explorer.refresh()
  end
end

---Connect to a database (with connection test)
---@param conn table Connection to connect to
function M.connect(conn)
  if not conn then
    vim.notify("Invalid connection", vim.log.levels.ERROR)
    return false
  end

  -- Test the connection first
  vim.notify("Testing connection to " .. conn.name .. "...", vim.log.levels.INFO)
  local executor = require("enhance.executor")
  local success, error_msg = executor.test_connection(conn)

  if not success then
    vim.notify("Connection failed: " .. (error_msg or "Unknown error"), vim.log.levels.ERROR)
    return false
  end

  -- Connection succeeded - set as current
  M.set_current(conn)

  -- Refresh explorer if it exists
  local explorer = require("enhance.explorer")
  if explorer.is_initialized() then
    explorer.refresh()
  end

  return true
end

---Show connection browser
function M.show_connections()
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  
  -- Header
  table.insert(lines, "Database Connections")
  table.insert(lines, "===================")
  table.insert(lines, "")
  
  -- Connection list
  for i, conn in ipairs(connections) do
    local current_marker = (current_connection and current_connection.name == conn.name) and "* " or "  "
    local line = string.format("%s[%d] %s (%s)", current_marker, i, conn.name, conn.type)
    table.insert(lines, line)
  end
  
  table.insert(lines, "")
  table.insert(lines, "Press <CR> to connect, q to close")
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'enhance-connections'
  vim.bo[buf].modifiable = false
  
  -- Open in split
  vim.cmd('vsplit')
  local browser_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(0, buf)

  -- Set keymaps
  vim.keymap.set('n', '<CR>', function()
    local line = vim.fn.line('.')
    -- Find connection index from line (accounting for header)
    local conn_idx = line - 3
    if conn_idx > 0 and conn_idx <= #connections then
      local conn = connections[conn_idx]
      -- Use the new connect function (includes connection test)
      if M.connect(conn) then
        -- Close the connection browser window
        if vim.api.nvim_win_is_valid(browser_win) then
          vim.api.nvim_win_close(browser_win, false)
        end
      end
    end
  end, { buffer = buf })
  
  vim.keymap.set('n', 'q', function()
    vim.cmd('close')
  end, { buffer = buf })
end

-- Expose for testing
M._connections = connections
M._disconnect = M.disconnect
M._connect = M.connect

return M

