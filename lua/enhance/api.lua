-- Stable public API for other plugins and user scripts.
-- Everything else under `enhance.*` is internal and may change between versions.
local M = {}

-- Bumped only for breaking changes to this module.
M.version = 1

---All configured connections.
---@return ConnectionConfig[]
function M.connections()
  return require('enhance.connections').get_connections() or {}
end

---Find a connection by name.
---@param name string
---@return ConnectionConfig?
function M.get_connection(name)
  return require('enhance.connections').get_connection(name)
end

---@param connection string|ConnectionConfig Name or connection table
---@return ConnectionConfig? connection
---@return string? err
local function resolve(connection)
  if type(connection) == 'string' then
    local found = M.get_connection(connection)
    if not found then return nil, 'Unknown enhance connection: ' .. connection end
    return found
  end
  if type(connection) == 'table' and connection.name and connection.type then
    return connection
  end
  return nil, 'Expected a connection name or connection table'
end

---Ask the user to pick a connection.
---@param on_choice fun(connection: ConnectionConfig?) Called with nil when cancelled or none exist
---@param opts? { prompt?: string }
function M.pick_connection(on_choice, opts)
  opts = opts or {}
  local connections = M.connections()
  if #connections == 0 then
    vim.notify('enhance: no connections configured', vim.log.levels.WARN)
    on_choice(nil)
    return
  end
  vim.ui.select(connections, {
    prompt = opts.prompt or 'Select connection',
    format_item = function(conn)
      return conn.name .. ' (' .. conn.type .. ')'
    end,
  }, on_choice)
end

---Run a query and show the results in enhance's results window.
---Completion is announced with `User EnhanceQueryDone` (see README).
---@param query string
---@param opts { connection: string|ConnectionConfig, bufnr?: integer } bufnr: buffer the query came from
---@return boolean ok
---@return string? err
function M.execute(query, opts)
  opts = opts or {}
  if type(query) ~= 'string' or vim.trim(query) == '' then
    return false, 'No query to execute'
  end
  local connection, err = resolve(opts.connection)
  if not connection then return false, err end
  require('enhance.executor').execute(connection, query, opts.bufnr)
  return true
end

---Make any SQL buffer connection-aware without adding it to the explorer:
---enables table/column completion (vim-dadbod-completion) for that connection.
---Running queries stays up to the caller (see `execute`).
---@param bufnr integer
---@param connection string|ConnectionConfig
---@return boolean ok
---@return string? err
function M.attach(bufnr, connection)
  if not vim.api.nvim_buf_is_valid(bufnr) then return false, 'Invalid buffer' end
  local conn, err = resolve(connection)
  if not conn then return false, err end
  vim.b[bufnr].enhance_attached = conn.name
  require('enhance.completion').setup(bufnr, conn)
  return true
end

---Undo `attach`.
---@param bufnr integer
function M.detach(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  if vim.b[bufnr].enhance_attached then
    vim.b[bufnr].enhance_attached = nil
    vim.b[bufnr].db = nil
    if vim.bo[bufnr].omnifunc == 'vim_dadbod_completion#omni' then
      vim.bo[bufnr].omnifunc = ''
    end
  end
end

---Name of the connection a buffer is attached to.
---@param bufnr integer
---@return string?
function M.attached(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].enhance_attached or nil
end

return M
