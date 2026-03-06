-- enhance.nvim - MySQL / MariaDB database module
-- Implements the database module contract for MySQL connections via mysql CLI

local M = {}

---MySQL does not yet support de-batch execution
---@type boolean
M.supports_debatch = false

---Options for building a mysql CLI command
---@class MysqlCmdOptions
---@field query string SQL statement to pass via -e flag

---Build a mysql command array for a MySQL/MariaDB connection.
---@param connection table MySQL connection
---@param opts MysqlCmdOptions
---@return string[] Command array ready for vim.fn.system / vim.fn.jobstart
function M.build_cmd(connection, opts)
  local cmd = { "mysql" }

  if connection.host then
    table.insert(cmd, "-h")
    table.insert(cmd, connection.host)
  end

  if connection.port then
    table.insert(cmd, "-P")
    table.insert(cmd, tostring(connection.port))
  end

  if connection.user or connection.username then
    table.insert(cmd, "-u")
    table.insert(cmd, connection.user or connection.username)
  end

  if connection.password then
    -- mysql expects -p<password> with no space
    table.insert(cmd, "-p" .. connection.password)
  end

  if connection.database then
    table.insert(cmd, connection.database)
  end

  table.insert(cmd, "-e")
  table.insert(cmd, opts.query)

  return cmd
end

---MySQL returns native row counts; no query rewriting is needed.
---@param statement_text string Raw SQL statement
---@return boolean is_dml  Always false
---@return string exec_query Statement unchanged
function M.prepare_query(statement_text)
  return false, statement_text
end

---MySQL exits non-zero on errors; output scanning is not required.
---@param output_lines string[]
---@return boolean Always false
function M.has_error(_output_lines)
  return false
end

---Test a MySQL connection by running a probe query.
---@param connection table MySQL connection
---@return boolean success
---@return string? error_msg
function M.test_connection(connection)
  local cmd = M.build_cmd(connection, { query = "SELECT 1;" })
  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return false, "Failed to connect to MySQL: " .. output
  end
  return true, nil
end

---Execute a single MySQL statement synchronously.
---MySQL does not currently support debatch mode; this is a contract stub
---that can be activated when supports_debatch is set to true.
---@param connection table MySQL connection
---@param statement_text string Single SQL statement
---@return table|nil parsed_result
---@return string|nil error_msg
---@return number duration  milliseconds
---@return number row_count
function M.execute_single(connection, statement_text)
  local start_time = vim.loop.hrtime()
  local cmd = M.build_cmd(connection, { query = statement_text })

  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error
  local duration = (vim.loop.hrtime() - start_time) / 1000000

  if exit_code ~= 0 then
    return nil, output, duration, 0
  end

  local output_lines = {}
  for line in output:gmatch("[^\r\n]+") do
    if line ~= "" and not line:match("^mysql: %[Warning%]") then
      table.insert(output_lines, line)
    end
  end

  local parser = require("enhance.parser")
  local parsed_result = parser.parse(output_lines, "mysql")

  return parsed_result, nil, duration, #(parsed_result and parsed_result.rows or {})
end

-- Expose internals for testing (M._function_name pattern)
M._build_cmd       = M.build_cmd
M._prepare_query   = M.prepare_query
M._has_error       = M.has_error
M._test_connection = M.test_connection
M._execute_single  = M.execute_single

return M

