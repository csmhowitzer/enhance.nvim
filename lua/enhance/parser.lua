-- enhance.nvim - Result Parser
-- Parses raw database output into structured format

local M = {}

---Normalize headers by replacing blank/empty headers with default names
---@param headers string[] Headers to normalize
---@return string[] Normalized headers
local function normalize_headers(headers)
  local normalized = {}
  for i, header in ipairs(headers) do
    -- Check if header is empty or only whitespace
    if header == "" or header:match("^%s*$") then
      table.insert(normalized, string.format("(column-%d)", i))
    else
      table.insert(normalized, header)
    end
  end
  return normalized
end

---Parse SQL Server (sqlcmd) output
---Format: COLUMN|DATA|TYPE with pipe separators
---@param lines string[] Raw output lines
---@return table Parsed result {headers: string[], rows: string[][], metadata: table}
function M.parse_sqlserver(lines)
  if not lines or #lines == 0 then
    return { headers = {}, rows = {}, metadata = {} }
  end

  local headers = {}
  local rows = {}
  local separator_idx = nil

  -- Find header and separator
  for i, line in ipairs(lines) do
    if line:match("^%-+|") or line:match("^%-+$") then
      separator_idx = i
      break
    end
  end

  if separator_idx and separator_idx > 1 then
    -- Parse headers from line before separator
    local header_line = lines[separator_idx - 1]
    for header in header_line:gmatch("[^|]+") do
      table.insert(headers, vim.trim(header))
    end

    -- Normalize headers (replace blank headers with default names)
    headers = normalize_headers(headers)

    -- Parse data rows (after separator, before footer)
    for i = separator_idx + 1, #lines do
      local line = lines[i]
      -- Stop at footer lines (rows affected, empty lines)
      if line:match("^%(.*rows? affected%)") or line == "" then
        break
      end

      local row = {}
      for cell in line:gmatch("[^|]+") do
        table.insert(row, vim.trim(cell))
      end

      if #row > 0 then
        table.insert(rows, row)
      end
    end
  end

  return {
    headers = headers,
    rows = rows,
    metadata = { db_type = "sqlserver" }
  }
end

---Find all separator line indices in SQLite output
---@param lines string[] Raw output lines
---@return number[] Array of separator line indices
local function find_all_separators(lines)
  local separators = {}
  for i, line in ipairs(lines) do
    if line:match("^[%-%s]+$") and line:match("%S") then
      table.insert(separators, i)
    end
  end
  return separators
end

---Parse a single SQLite result set
---@param lines string[] Raw output lines
---@param separator_idx number Index of separator line
---@param end_idx number? Index to stop parsing (exclusive), nil for end of lines
---@return table Parsed result {headers: string[], rows: string[][]}
local function parse_single_result_set(lines, separator_idx, end_idx)
  local headers = {}
  local rows = {}

  if not separator_idx or separator_idx <= 1 then
    return { headers = headers, rows = rows }
  end

  -- Calculate column positions from separator line
  local col_positions = {}
  local separator_line = lines[separator_idx]
  local start_pos = 1
  for dash_group in separator_line:gmatch("%S+") do
    local pos = separator_line:find(dash_group, start_pos, true)
    table.insert(col_positions, { start = pos, width = #dash_group })
    start_pos = pos + #dash_group
  end

  -- Parse headers from line before separator
  local header_line = lines[separator_idx - 1]
  for header in header_line:gmatch("%S+") do
    table.insert(headers, header)
  end

  -- Ensure we have as many headers as columns
  while #headers < #col_positions do
    table.insert(headers, "")
  end

  -- Normalize headers
  headers = normalize_headers(headers)

  -- Parse data rows using column positions
  -- If we have end_idx, stop before the next header (which is at end_idx - 1)
  local stop_at = end_idx and (end_idx - 1) or (#lines + 1)
  for i = separator_idx + 1, stop_at - 1 do
    local line = lines[i]

    -- Stop at empty line or next separator
    if line == "" or line:match("^[%-%s]+$") then
      break
    end

    local row = {}
    for _, col in ipairs(col_positions) do
      local cell = line:sub(col.start, col.start + col.width - 1)
      table.insert(row, vim.trim(cell))
    end

    if #row > 0 then
      table.insert(rows, row)
    end
  end

  return { headers = headers, rows = rows }
end

---Parse SQLite (sqlite3 -column -header) output
---Format: Space-aligned columns with dash separator
---@param lines string[] Raw output lines
---@return table Parsed result {headers: string[], rows: string[][], metadata: table} or {multiple_results: boolean, result_sets: table[], metadata: table}
function M.parse_sqlite(lines)
  if not lines or #lines == 0 then
    return { headers = {}, rows = {}, metadata = {} }
  end

  -- Find all separator lines
  local separators = find_all_separators(lines)

  if #separators == 0 then
    return { headers = {}, rows = {}, metadata = { db_type = "sqlite" } }
  end

  -- Single result set - maintain backward compatibility
  if #separators == 1 then
    local result = parse_single_result_set(lines, separators[1], nil)
    return {
      headers = result.headers,
      rows = result.rows,
      metadata = { db_type = "sqlite" }
    }
  end

  -- Multiple result sets
  local result_sets = {}
  for i, sep_idx in ipairs(separators) do
    local next_sep_idx = separators[i + 1]
    local result = parse_single_result_set(lines, sep_idx, next_sep_idx)
    table.insert(result_sets, {
      headers = result.headers,
      rows = result.rows,
      metadata = { db_type = "sqlite" }
    })
  end

  return {
    multiple_results = true,
    result_sets = result_sets,
    metadata = { db_type = "sqlite" }
  }
end

---Parse MySQL output
---Format: Tab-separated values (TSV) from mysql -e flag
---@param lines string[] Raw output lines
---@return table Parsed result {headers: string[], rows: string[][], metadata: table}
function M.parse_mysql(lines)
  if not lines or #lines == 0 then
    return { headers = {}, rows = {}, metadata = {} }
  end

  local headers = {}
  local rows = {}

  -- Check if this is TSV format (tab-separated) or ASCII table format (|)
  local is_tsv = #lines > 0 and lines[1]:match("\t") and not lines[1]:match("^%+")

  if is_tsv then
    -- TSV format: first line is headers, rest are data
    if #lines > 0 then
      -- Parse headers
      for header in lines[1]:gmatch("[^\t]+") do
        table.insert(headers, vim.trim(header))
      end

      -- Normalize headers (replace blank headers with default names)
      headers = normalize_headers(headers)

      -- Parse data rows
      for i = 2, #lines do
        local line = lines[i]
        local row = {}
        for cell in line:gmatch("[^\t]+") do
          table.insert(row, vim.trim(cell))
        end
        if #row > 0 then
          table.insert(rows, row)
        end
      end
    end
  else
    -- ASCII table format with +----+ borders
    local header_idx = nil
    for i, line in ipairs(lines) do
      if line:match("^|") and not line:match("^%+") then
        header_idx = i
        break
      end
    end

    if header_idx then
      -- Parse headers (keep blank headers for normalization)
      local header_line = lines[header_idx]
      for header in header_line:gmatch("[^|]+") do
        table.insert(headers, vim.trim(header))
      end

      -- Normalize headers (replace blank headers with default names)
      headers = normalize_headers(headers)

      -- Parse data rows (skip borders)
      for i = header_idx + 1, #lines do
        local line = lines[i]
        -- Stop at footer lines (not border lines)
        if line:match("rows? in set") or line:match("rows? affected") then
          break
        end

        -- Skip border lines, process data lines
        if line:match("^|") and not line:match("^%+") then
          local row = {}
          for cell in line:gmatch("[^|]+") do
            local trimmed = vim.trim(cell)
            if trimmed ~= "" then
              table.insert(row, trimmed)
            end
          end
          if #row > 0 then
            table.insert(rows, row)
          end
        end
      end
    end
  end

  return {
    headers = headers,
    rows = rows,
    metadata = { db_type = "mysql" }
  }
end

---Parse PostgreSQL (psql) output
---Format: Simple table with | separators
---@param lines string[] Raw output lines
---@return table Parsed result {headers: string[], rows: string[][], metadata: table}
function M.parse_postgresql(lines)
  if not lines or #lines == 0 then
    return { headers = {}, rows = {}, metadata = {} }
  end

  local headers = {}
  local rows = {}
  local separator_idx = nil

  -- Find separator line (dashes with optional + at intersections)
  -- Single column: "----"
  -- Multi column: "----+----"
  for i, line in ipairs(lines) do
    if line:match("^%-+%+") or line:match("^%s*%-+%+") or line:match("^%s*%-+%s*$") then
      separator_idx = i
      break
    end
  end

  if separator_idx and separator_idx > 1 then
    -- Parse headers from line before separator
    local header_line = lines[separator_idx - 1]

    -- Check if this is a multi-column table (has | separators)
    if header_line:match("|") then
      -- Multi-column: split by |
      for header in header_line:gmatch("[^|]+") do
        table.insert(headers, vim.trim(header))
      end
    else
      -- Single column: entire line is the header
      table.insert(headers, vim.trim(header_line))
    end

    -- Normalize headers (replace blank headers with default names)
    headers = normalize_headers(headers)

    -- Parse data rows
    for i = separator_idx + 1, #lines do
      local line = lines[i]
      -- Stop at footer
      if line:match("^%(.*rows?%)") or line:match("^[A-Z]+%s+%d+%s+%d+") then
        break
      end

      -- Check if multi-column (has |) or single column
      if line:match("|") then
        -- Multi-column: split by |
        local row = {}
        for cell in line:gmatch("[^|]+") do
          local trimmed = vim.trim(cell)
          if trimmed ~= "" then
            table.insert(row, trimmed)
          end
        end
        if #row > 0 then
          table.insert(rows, row)
        end
      else
        -- Single column: entire line is the value
        local trimmed = vim.trim(line)
        if trimmed ~= "" then
          table.insert(rows, { trimmed })
        end
      end
    end
  end

  return {
    headers = headers,
    rows = rows,
    metadata = { db_type = "postgresql" }
  }
end

---Auto-detect database type and parse accordingly
---@param lines string[] Raw output lines
---@param db_type string? Known database type (optional)
---@return table Parsed result {headers: string[], rows: string[][], metadata: table}
function M.parse(lines, db_type)
  if not lines or #lines == 0 then
    return { headers = {}, rows = {}, metadata = {} }
  end

  -- If db_type is provided, use specific parser
  if db_type then
    local normalized = db_type:lower():gsub("[%s%-_]", "")
    if normalized == "sqlserver" or normalized == "mssql" then
      return M.parse_sqlserver(lines)
    elseif normalized == "sqlite" then
      return M.parse_sqlite(lines)
    elseif normalized == "mysql" or normalized == "mariadb" then
      return M.parse_mysql(lines)
    elseif normalized == "postgres" or normalized == "postgresql" then
      return M.parse_postgresql(lines)
    end
  end

  -- Auto-detect based on format
  local first_few = table.concat(vim.list_slice(lines, 1, math.min(5, #lines)), "\n")

  if first_few:match("|") and first_few:match("%-+|") then
    return M.parse_sqlserver(lines)
  elseif first_few:match("^%+%-") then
    return M.parse_mysql(lines)
  elseif first_few:match("^%s*%-+%+") then
    return M.parse_postgresql(lines)
  elseif first_few:match("^[%-%s]+$") then
    return M.parse_sqlite(lines)
  end

  -- Fallback: return raw lines as single column
  return {
    headers = { "Result" },
    rows = vim.tbl_map(function(line) return { line } end, lines),
    metadata = { db_type = "unknown" }
  }
end

-- Expose internal functions for testing
M._normalize_headers = normalize_headers
M._find_all_separators = find_all_separators
M._parse_single_result_set = parse_single_result_set
M._parse_sqlserver = M.parse_sqlserver
M._parse_sqlite = M.parse_sqlite
M._parse_mysql = M.parse_mysql
M._parse_postgresql = M.parse_postgresql

return M

