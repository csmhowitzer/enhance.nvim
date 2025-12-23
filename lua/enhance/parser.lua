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

---Parse SQLite (sqlite3 -column -header) output
---Format: Space-aligned columns with dash separator
---@param lines string[] Raw output lines
---@return table Parsed result {headers: string[], rows: string[][], metadata: table}
function M.parse_sqlite(lines)
  if not lines or #lines == 0 then
    return { headers = {}, rows = {}, metadata = {} }
  end

  local headers = {}
  local rows = {}
  local separator_idx = nil

  -- Find separator line (all dashes and spaces)
  for i, line in ipairs(lines) do
    if line:match("^[%-%s]+$") then
      separator_idx = i
      break
    end
  end

  if separator_idx and separator_idx > 1 then
    -- Calculate column positions from separator line first
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

    -- Ensure we have as many headers as columns (fill missing with empty strings)
    while #headers < #col_positions do
      table.insert(headers, "")
    end

    -- Normalize headers (replace blank headers with default names)
    headers = normalize_headers(headers)

    -- Parse data rows using column positions
    for i = separator_idx + 1, #lines do
      local line = lines[i]
      if line == "" then
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
  end

  return {
    headers = headers,
    rows = rows,
    metadata = { db_type = "sqlite" }
  }
end

---Parse MySQL output
---Format: ASCII table with +----+ borders
---@param lines string[] Raw output lines
---@return table Parsed result {headers: string[], rows: string[][], metadata: table}
function M.parse_mysql(lines)
  if not lines or #lines == 0 then
    return { headers = {}, rows = {}, metadata = {} }
  end

  local headers = {}
  local rows = {}

  -- Find header line (between first two border lines)
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
M._parse_sqlserver = M.parse_sqlserver
M._parse_sqlite = M.parse_sqlite
M._parse_mysql = M.parse_mysql
M._parse_postgresql = M.parse_postgresql

return M

