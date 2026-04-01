-- enhance.nvim - SQL Server database module
-- Implements the database module contract for SQL Server connections via sqlcmd CLI

local M = {}

---SQL Server supports de-batch execution (each statement run individually)
---@type boolean
M.supports_debatch = true

---Build a sqlcmd command array for a SQL Server connection.
---@class SqlcmdOptions
---@field query string Inline query string for -Q flag
---@field format boolean? Include pipe/trim/width formatting flags (default: true)
---@field no_headers boolean? Suppress column headers with -h -1 (default: false)
---
---@param connection table SQL Server connection
---@param opts SqlcmdOptions
---@return string[] Command array ready for vim.fn.system / vim.fn.jobstart
function M.build_cmd(connection, opts)
  local cmd = { "sqlcmd" }

  -- Server / database
  if connection.server or connection.host then
    table.insert(cmd, "-S")
    table.insert(cmd, connection.server or connection.host)
  end
  if connection.database then
    table.insert(cmd, "-d")
    table.insert(cmd, connection.database)
  end

  -- Authentication
  if connection.user or connection.username then
    table.insert(cmd, "-U")
    table.insert(cmd, connection.user or connection.username)
    if connection.password then
      table.insert(cmd, "-P")
      table.insert(cmd, connection.password)
    end
  else
    table.insert(cmd, "-E") -- Windows Authentication
  end

  -- Trust server certificate (for self-signed certs in dev/test environments)
  if connection.trust_server_certificate ~= false then
    table.insert(cmd, "-C")
  end

  -- Output formatting flags (pipe separator, trim spaces, wide column width)
  if opts.format ~= false then
    table.insert(cmd, "-s")
    table.insert(cmd, "|")
    table.insert(cmd, "-W")
    -- Note: -y (variable-length type display width) is intentionally omitted.
    -- On Windows sqlcmd, -y and -W are mutually exclusive and will error.
    -- sqlcmd defaults to 256 chars for varchar(max)/nvarchar(max) without -y.
    -- This is a known constraint that affects the truncated column viewer design
    -- (see enhance-dev-notes/HANDOFF_CONTEXT.md for details).
  end

  -- Suppress headers (used for connection tests)
  if opts.no_headers then
    table.insert(cmd, "-h")
    table.insert(cmd, "-1")
  end

  -- Inline query
  table.insert(cmd, "-Q")
  table.insert(cmd, opts.query)

  return cmd
end

---SQL Server returns native row counts; no query rewriting is needed.
---@param statement_text string Raw SQL statement
---@return boolean is_dml  Always false — SQL Server handles DML counts natively
---@return string exec_query Statement unchanged
function M.prepare_query(statement_text)
  return false, statement_text
end

---Check output lines for SQL Server error patterns.
---sqlcmd exits 0 even on SQL errors, so output scanning is required.
---@param output_lines string[]
---@return boolean
function M.has_error(output_lines)
  for _, line in ipairs(output_lines) do
    if line:match("Msg %d+, Level %d+") then
      return true
    end
  end
  return false
end

---Test a SQL Server connection by running a probe query via sqlcmd.
---@param connection table SQL Server connection
---@return boolean success
---@return string? error_msg
function M.test_connection(connection)
  local cmd = M.build_cmd(connection, { query = "SELECT 1;", format = false, no_headers = true })
  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return false, "Failed to connect to SQL Server: " .. output
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

---Private: parse a single SQL Server result set chunk.
---Auto-detects pipe-separated (ID|Name) or space-separated fixed-width format.
---@param chunk string[] Lines from start of result set up to (not including) the boundary line
---@return table {headers: string[], rows: string[][]}
local function parse_chunk(chunk)
  if not chunk or #chunk == 0 then return { headers = {}, rows = {} } end
  local headers, rows, sep_idx = {}, {}, nil
  for i, line in ipairs(chunk) do
    if line:match("^%-+") and line:match("^[%-%s|]+$") then sep_idx = i; break end
  end
  if not sep_idx or sep_idx <= 1 then return { headers = headers, rows = rows } end
  local header_line    = chunk[sep_idx - 1]
  local separator_line = chunk[sep_idx]
  if header_line:match("|") then
    -- Pipe-separated format
    for h in header_line:gmatch("[^|]+") do table.insert(headers, vim.trim(h)) end
    headers = normalize_headers(headers)
    for i = sep_idx + 1, #chunk do
      local line = chunk[i]
      if line:match("^%(%d+ rows? affected%)") or line == "" then break end
      local row = {}
      for cell in line:gmatch("[^|]+") do table.insert(row, vim.trim(cell)) end
      if #row > 0 then table.insert(rows, row) end
    end
  else
    -- Fixed-width space-separated format
    local col_pos, sp = {}, 1
    for dg in separator_line:gmatch("%-+") do
      local pos = separator_line:find(dg, sp, true)
      table.insert(col_pos, { start = pos, length = #dg })
      sp = pos + #dg + 1
    end
    for _, col in ipairs(col_pos) do
      table.insert(headers, vim.trim(header_line:sub(col.start, col.start + col.length - 1)))
    end
    headers = normalize_headers(headers)
    for i = sep_idx + 1, #chunk do
      local line = chunk[i]
      if line:match("^%(%d+ rows? affected%)") or line == "" then break end
      local row = {}
      if #col_pos == 1 then
        table.insert(row, vim.trim(line))
      else
        for _, col in ipairs(col_pos) do
          table.insert(row, vim.trim(line:sub(col.start, col.start + col.length - 1)))
        end
      end
      if #row > 0 then table.insert(rows, row) end
    end
  end
  return { headers = headers, rows = rows }
end

---Grammar descriptor for the normalized parser pipeline.
---SQL Server uses footer mode: "(X rows affected)" marks the end of each result set.
---DML-only result sets (no headers/rows, only a row count) are included.
---@class DbGrammar
M.grammar = {
  db_type          = "sqlserver",
  boundary_mode    = "footer",
  boundary_match   = function(line) return line:match("^%(%d+ rows? affected%)") ~= nil end,
  row_count_pattern = "%((%d+) rows? affected%)",
  include_dml_only = true,
  parse_chunk      = parse_chunk,
}

---Execute a single SQL Server statement synchronously and return a parsed result.
---@param connection table SQL Server connection
---@param statement_text string Single SQL statement
---@return table|nil parsed_result  nil on error
---@return string|nil error_msg     populated on error
---@return number duration          milliseconds
---@return number row_count
function M.execute_single(connection, statement_text)
  local start_time = vim.loop.hrtime()
  local cmd = M.build_cmd(connection, { query = statement_text })

  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error
  local duration = (vim.loop.hrtime() - start_time) / 1000000 -- ms

  local output_lines = {}
  for line in output:gmatch("[^\r\n]+") do
    if line ~= "" then
      table.insert(output_lines, line)
    end
  end

  if M.has_error(output_lines) then
    return nil, table.concat(output_lines, "\n"), duration, 0
  end

  if exit_code ~= 0 then
    return nil, output, duration, 0
  end

  local row_count = 0
  for _, line in ipairs(output_lines) do
    local count = line:match("%((%d+) rows? affected%)")
    if count then
      row_count = tonumber(count) or 0
      break
    end
  end

  local parser = require("enhance.parser")
  local parsed_result = parser.parse(output_lines, M.grammar)

  return parsed_result, nil, duration, row_count
end

-- Expose internals for testing (M._function_name pattern)
M._build_cmd        = M.build_cmd
M._prepare_query    = M.prepare_query
M._has_error        = M.has_error
M._test_connection  = M.test_connection
M._execute_single   = M.execute_single

return M

