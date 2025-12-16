-- enhance.nvim - Connection management
-- Handles database connections and connection browser

local M = {}

---@type table[]
local connections = {}

---@type table?
local current_connection = nil

---Setup connections from configuration
---@param conn_list table[] List of connections
function M.setup(conn_list)
  connections = conn_list or {}
  
  -- Add default SQLite connection for testing if no connections provided
  if #connections == 0 then
    connections = {
      {
        name = "Test SQLite",
        type = "sqlite",
        path = vim.fn.expand("~/.local/share/nvim/enhance/test.db"),
      }
    }
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
      M.set_current(connections[conn_idx])
      require("enhance.query").create_query_buffer(connections[conn_idx])
      -- Close the connection browser window specifically
      if vim.api.nvim_win_is_valid(browser_win) then
        vim.api.nvim_win_close(browser_win, false)
      end
    end
  end, { buffer = buf })
  
  vim.keymap.set('n', 'q', function()
    vim.cmd('close')
  end, { buffer = buf })
end

-- Expose for testing
M._connections = connections

return M

