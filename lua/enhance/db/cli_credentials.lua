-- Child-only credentials for legacy CLI probes and catalog lookups.
local M = {}

---@param connection table
---@param db_type string
---@return table<string, string>
function M.env(connection, db_type)
  local key = ({ sqlserver = 'SQLCMDPASSWORD', mssql = 'SQLCMDPASSWORD',
    mysql = 'MYSQL_PWD', mariadb = 'MYSQL_PWD',
    postgres = 'PGPASSWORD', postgresql = 'PGPASSWORD' })[db_type]
  -- An empty value masks any password inherited from the editor for this child.
  return key and { [key] = connection.password or '' } or {}
end

---@param cmd string[]
---@param connection table
---@param db_type string
---@return string output
---@return integer exit_code
function M.system(cmd, connection, db_type)
  local ok, result = pcall(function()
    return vim.system(cmd, { env = M.env(connection, db_type), text = true, timeout = 30000 }):wait()
  end)
  if not ok then return 'Failed to start database CLI', -1 end
  if result.code == 124 then return 'Database CLI timed out after 30 seconds', 124 end
  local output = (result.stdout or '') .. (result.stderr or '')
  return output, result.code or -1
end

---Launch a bounded metadata/probe CLI without blocking the editor.
---@param cmd string[]
---@param connection table
---@param db_type string
---@param callback fun(output: string, exit_code: integer)
---@return table? process
function M.system_async(cmd, connection, db_type, callback)
  local ok, process = pcall(vim.system, cmd, {
    env = M.env(connection, db_type), text = true, timeout = 30000,
  }, function(result)
    vim.schedule(function()
      if result.code == 124 then
        callback('Database CLI timed out after 30 seconds', 124)
      else
        callback((result.stdout or '') .. (result.stderr or ''), result.code or -1)
      end
    end)
  end)
  if not ok or not process then
    vim.schedule(function() callback('Failed to start database CLI', -1) end)
    return nil
  end
  return process
end

return M
