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
  local result = vim.system(cmd, { env = M.env(connection, db_type), text = true }):wait()
  local output = (result.stdout or '') .. (result.stderr or '')
  return output, result.code or -1
end

return M
