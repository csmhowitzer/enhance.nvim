-- enhance.nvim - SQLite database module
-- Implements the database module contract for SQLite connections via sqlite3 CLI

local M = {}

---SQLite supports de-batch execution (each statement run individually)
---@type boolean
M.supports_debatch = true

---Test a SQLite connection by checking file accessibility and running a probe query
---@param connection table SQLite connection with .path field
---@return boolean success
---@return string? error_msg
function M.test_connection(connection)
  local db_path = vim.fn.expand(connection.path)

  if vim.fn.filereadable(db_path) == 0 then
    return false, "Database file not found: " .. db_path
  end

  local output = vim.fn.system({ "sqlite3", db_path, "SELECT 1;" })
  if vim.v.shell_error ~= 0 then
    return false, "Failed to connect to SQLite database: " .. output
  end

  return true, nil
end

---Detect if a statement is DML and append SELECT changes() if so.
---SQLite does not natively return a row-count for DML; changes() gives us that.
---@param statement_text string Raw SQL statement
---@return boolean is_dml
---@return string exec_query Statement ready for execution (changes() appended for DML)
function M.prepare_query(statement_text)
  local trimmed = statement_text:upper():gsub("^%s+", "")
  local is_dml = trimmed:match("^INSERT%s") ~= nil
             or trimmed:match("^UPDATE%s") ~= nil
             or trimmed:match("^DELETE%s") ~= nil
  local exec_query = is_dml and (statement_text .. "; SELECT changes();") or statement_text
  return is_dml, exec_query
end

---Check output lines for detectable SQL errors.
---SQLite signals errors via non-zero exit code rather than output patterns,
---so this always returns false (error detection is handled by exit code in execute_single).
---@param _output_lines string[]
---@return boolean
function M.has_error(_output_lines)
  return false
end

---Execute a single SQLite statement synchronously and return a parsed result.
---For DML statements, changes() is appended to capture the affected-row count.
---@param connection table SQLite connection
---@param statement_text string Single SQL statement
---@return table|nil parsed_result  nil on error
---@return string|nil error_msg     populated on error
---@return number duration          milliseconds
---@return number row_count
function M.execute_single(connection, statement_text)
  local start_time = vim.loop.hrtime()
  local db_path = vim.fn.expand(connection.path)

  local is_dml, exec_query = M.prepare_query(statement_text)

  local cmd = string.format(
    "sqlite3 %s -column -header %s",
    vim.fn.shellescape(db_path),
    vim.fn.shellescape(exec_query)
  )

  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error
  local duration = (vim.loop.hrtime() - start_time) / 1000000 -- ms

  -- Split output into non-empty lines
  local output_lines = {}
  for line in output:gmatch("[^\r\n]+") do
    if line ~= "" then
      table.insert(output_lines, line)
    end
  end

  if exit_code ~= 0 then
    return nil, output, duration, 0
  end

  local row_count = 0

  if is_dml and #output_lines > 0 then
    -- DML: the last output line is the changes() integer value.
    -- sqlite3 outputs: header line, separator line, value line.
    local changes = tonumber(output_lines[#output_lines])
    if changes then
      row_count = changes
      -- Remove the three changes() lines (value, separator, header) if present
      if #output_lines >= 3 then
        table.remove(output_lines) -- value
        table.remove(output_lines) -- separator
        table.remove(output_lines) -- header ("changes()")
      end
    end
  else
    -- SELECT: count non-empty data rows (skip header line + separator line at top)
    for i = 3, #output_lines do
      if output_lines[i]:match("%S") then
        row_count = row_count + 1
      end
    end
  end

  local parser = require("enhance.parser")
  local parsed_result = parser.parse(output_lines, "sqlite")

  return parsed_result, nil, duration, row_count
end

-- Expose internals for testing (M._function_name pattern)
M._test_connection  = M.test_connection
M._prepare_query    = M.prepare_query
M._has_error        = M.has_error
M._execute_single   = M.execute_single

return M

