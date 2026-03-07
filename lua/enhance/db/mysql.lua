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

---Private: normalize blank/empty column headers with positional fallbacks
local function normalize_headers(headers)
  local out = {}
  for i, h in ipairs(headers) do
    out[i] = (h == "" or h:match("^%s*$")) and string.format("(column-%d)", i) or h
  end
  return out
end

---Private: parse a single MySQL result set chunk.
---Auto-detects TSV (tab-separated) vs ASCII table (pipe-bordered) format.
---@param chunk string[] Lines for this result set (up to but not including the footer)
---@return table {headers: string[], rows: string[][]}
local function parse_chunk(chunk)
  if not chunk or #chunk == 0 then return { headers = {}, rows = {} } end
  local headers, rows = {}, {}
  local is_tsv = chunk[1]:match("\t") and not chunk[1]:match("^%+")
  if is_tsv then
    for h in chunk[1]:gmatch("[^\t]+") do table.insert(headers, vim.trim(h)) end
    headers = normalize_headers(headers)
    for i = 2, #chunk do
      local line = chunk[i]
      if line:match("rows? in set") or line:match("rows? affected") then break end
      local row = {}
      for cell in line:gmatch("[^\t]+") do table.insert(row, vim.trim(cell)) end
      if #row > 0 then table.insert(rows, row) end
    end
  else
    -- ASCII table: first pipe-row (not a border) is the header
    local header_idx = nil
    for i, line in ipairs(chunk) do
      if line:match("^|") and not line:match("^%+") then header_idx = i; break end
    end
    if header_idx then
      for h in chunk[header_idx]:gmatch("[^|]+") do table.insert(headers, vim.trim(h)) end
      headers = normalize_headers(headers)
      for i = header_idx + 1, #chunk do
        local line = chunk[i]
        if line:match("rows? in set") or line:match("rows? affected") then break end
        if line:match("^|") and not line:match("^%+") then
          local row = {}
          for cell in line:gmatch("[^|]+") do
            local t = vim.trim(cell)
            if t ~= "" then table.insert(row, t) end
          end
          if #row > 0 then table.insert(rows, row) end
        end
      end
    end
  end
  return { headers = headers, rows = rows }
end

---Grammar descriptor for the normalized parser pipeline.
---MySQL uses footer mode: "X rows in set" marks the end of each result set.
---@type DbGrammar
M.grammar = {
  db_type        = "mysql",
  boundary_mode  = "footer",
  boundary_match = function(line) return line:match("rows? in set") ~= nil end,
  parse_chunk    = parse_chunk,
}

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
  local parsed_result = parser.parse(output_lines, M.grammar)

  return parsed_result, nil, duration, #(parsed_result and parsed_result.rows or {})
end

-- Expose internals for testing (M._function_name pattern)
M._build_cmd       = M.build_cmd
M._prepare_query   = M.prepare_query
M._has_error       = M.has_error
M._test_connection = M.test_connection
M._execute_single  = M.execute_single

return M

