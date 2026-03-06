-- enhance.nvim - PostgreSQL database module
-- Implements the database module contract for PostgreSQL connections via psql CLI

local M = {}

---PostgreSQL does not yet support de-batch execution
---@type boolean
M.supports_debatch = false

---Options for building a psql CLI command
---@class PsqlCmdOptions
---@field query string SQL statement to pass via -c flag

---Build a psql command array for a PostgreSQL connection.
---Note: password is handled via PGPASSWORD env var, not as a flag.
---`test_connection` and `execute_single` manage PGPASSWORD set/clear around each call.
---@param connection table PostgreSQL connection
---@param opts PsqlCmdOptions
---@return string[] Command array ready for vim.fn.system / vim.fn.jobstart
function M.build_cmd(connection, opts)
  local cmd = {
    "psql",
    "-h", connection.host or "localhost",
    "-d", connection.database,
  }

  if connection.port then
    table.insert(cmd, "-p")
    table.insert(cmd, tostring(connection.port))
  end

  if connection.user or connection.username then
    table.insert(cmd, "-U")
    table.insert(cmd, connection.user or connection.username)
  end

  -- No password flag: use PGPASSWORD env var (set by caller)
  -- Add -w to prevent interactive password prompt when no password configured
  if not connection.password then
    table.insert(cmd, "-w")
  end

  table.insert(cmd, "-c")
  table.insert(cmd, opts.query)

  return cmd
end

---PostgreSQL returns native row counts; no query rewriting is needed.
---@param statement_text string Raw SQL statement
---@return boolean is_dml  Always false
---@return string exec_query Statement unchanged
function M.prepare_query(statement_text)
  return false, statement_text
end

---PostgreSQL exits non-zero on errors; output scanning is not required.
---@param output_lines string[]
---@return boolean Always false
function M.has_error(_output_lines)
  return false
end

---Test a PostgreSQL connection by running a probe query.
---Manages PGPASSWORD env var for the duration of the call.
---@param connection table PostgreSQL connection
---@return boolean success
---@return string? error_msg
function M.test_connection(connection)
  if connection.password then
    vim.fn.setenv("PGPASSWORD", connection.password)
  end

  local cmd = M.build_cmd(connection, { query = "SELECT 1;" })
  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  if connection.password then
    vim.fn.setenv("PGPASSWORD", nil)
  end

  if exit_code ~= 0 then
    return false, "Failed to connect to PostgreSQL: " .. output
  end
  return true, nil
end

---Execute a single PostgreSQL statement synchronously.
---PostgreSQL does not currently support debatch mode; this is a contract stub.
---Manages PGPASSWORD env var for the duration of the call.
---@param connection table PostgreSQL connection
---@param statement_text string Single SQL statement
---@return table|nil parsed_result
---@return string|nil error_msg
---@return number duration  milliseconds
---@return number row_count
function M.execute_single(connection, statement_text)
  local start_time = vim.loop.hrtime()

  if connection.password then
    vim.fn.setenv("PGPASSWORD", connection.password)
  end

  local cmd = M.build_cmd(connection, { query = statement_text })
  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error
  local duration = (vim.loop.hrtime() - start_time) / 1000000

  if connection.password then
    vim.fn.setenv("PGPASSWORD", nil)
  end

  if exit_code ~= 0 then
    return nil, output, duration, 0
  end

  local output_lines = {}
  for line in output:gmatch("[^\r\n]+") do
    if line ~= "" then
      table.insert(output_lines, line)
    end
  end

  local parser = require("enhance.parser")
  local parsed_result = parser.parse(output_lines, "postgres")

  return parsed_result, nil, duration, #(parsed_result and parsed_result.rows or {})
end

-- Expose internals for testing (M._function_name pattern)
M._build_cmd       = M.build_cmd
M._prepare_query   = M.prepare_query
M._has_error       = M.has_error
M._test_connection = M.test_connection
M._execute_single  = M.execute_single

return M

