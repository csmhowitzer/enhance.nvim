-- Connect Enhance SQL Server query buffers to vim-dadbod-completion.
local M = {}

---Encode connection fields without changing their values for Dadbod's URL parser.
---@param value string
---@return string
local function encode(value)
  return tostring(value):gsub('([^%w%-._~])', function(char)
    return string.format('%%%02X', string.byte(char))
  end)
end

---Build the Dadbod SQL Server URL from an Enhance connection.
---@param connection ConnectionConfig
---@return string? url
function M.sqlserver_url(connection)
  if type(connection) ~= 'table' then return nil end
  local db_type = type(connection.type) == 'string'
    and connection.type:lower():gsub('[%s%-_]', '') or ''
  if db_type ~= 'sqlserver' and db_type ~= 'mssql' then return nil end

  local server = connection.server or connection.host
  if not server or not connection.database then return nil end
  local host, server_port = server:match('^([^,]+),(%d+)$')
  host = host or server
  local port = connection.port or server_port
  local url = 'sqlserver://' .. encode(host)
    .. (port and ':' .. tostring(port) or '') .. '/' .. encode(connection.database)
  local params = {}
  local user = connection.user or connection.username
  if user then
    params[#params + 1] = 'user=' .. encode(user)
    if connection.password then
      params[#params + 1] = 'password=' .. encode(connection.password)
    end
  end
  if connection.trust_server_certificate ~= false then
    params[#params + 1] = 'TrustServerCertificate=true'
  end
  if #params > 0 then url = url .. ';' .. table.concat(params, ';') end
  return url
end

---Enable database-aware completion only on Enhance SQL Server query buffers.
---@param bufnr integer
---@param connection ConnectionConfig?
function M.setup(bufnr, connection)
  if vim.bo[bufnr].filetype ~= 'sql' then return end
  local url = M.sqlserver_url(connection)
  if not url then return end
  vim.b[bufnr].db = url
  vim.bo[bufnr].omnifunc = 'vim_dadbod_completion#omni'
end

return M
