-- enhance.nvim - Result Parser (normalized grammar-driven pipeline)
-- Steps A–F always execute; DB-specific logic lives in each lua/enhance/db/*.lua grammar.
-- DB modules pass their M.grammar table to M.parse(lines, grammar); the parser is DB-agnostic.

local M = {}

-- B: Find all boundary line indices using grammar.boundary_match
-- Returns {} immediately when boundary_match is nil (early-exit for grammars without boundaries)
local function find_boundaries(lines, grammar)
  if not grammar or not grammar.boundary_match then return {} end
  local result = {}
  for i, line in ipairs(lines) do
    if grammar.boundary_match(line) then table.insert(result, i) end
  end
  return result
end

-- Shared utility: replace empty/blank headers with positional fallbacks
-- Kept in parser for the _normalize_headers test alias
local function normalize_headers(headers)
  local out = {}
  for i, h in ipairs(headers) do
    out[i] = (h == "" or h:match("^%s*$")) and string.format("(column-%d)", i) or h
  end
  return out
end

-- C+D+E+F: Footer mode — boundary line appears AFTER each result set (SQL Server, MySQL)
local function parse_footer_mode(lines, grammar)
  local boundaries = find_boundaries(lines, grammar)
  local db = grammar.db_type

  if #boundaries == 0 then
    local parsed = grammar.parse_chunk(lines)
    return { headers = parsed.headers, rows = parsed.rows, metadata = { db_type = db } }
  end

  if #boundaries == 1 then
    local chunk = vim.list_slice(lines, 1, boundaries[1] - 1)
    local parsed = grammar.parse_chunk(chunk)
    local row_count = nil
    if grammar.row_count_pattern then
      row_count = tonumber(lines[boundaries[1]]:match(grammar.row_count_pattern))
    end
    return {
      headers  = parsed.headers,
      rows     = parsed.rows,
      metadata = { db_type = db, row_count = row_count },
    }
  end

  -- Multiple boundaries → multiple result sets
  local result_sets, start_idx = {}, 1
  for _, bidx in ipairs(boundaries) do
    local chunk = vim.list_slice(lines, start_idx, bidx - 1)
    local parsed = grammar.parse_chunk(chunk)
    local row_count = nil
    if grammar.row_count_pattern then
      row_count = tonumber(lines[bidx]:match(grammar.row_count_pattern))
    end
    local include = #parsed.headers > 0 or #parsed.rows > 0
    if grammar.include_dml_only then include = include or (row_count ~= nil) end
    if include then
      table.insert(result_sets, {
        headers  = parsed.headers,
        rows     = parsed.rows,
        metadata = { db_type = db, row_count = row_count },
      })
    end
    start_idx = bidx + 1
  end
  return { multiple_results = true, result_sets = result_sets, metadata = { db_type = db } }
end

-- C+D+E+F: Separator mode — boundary line appears BEFORE each result set (SQLite, PostgreSQL)
local function parse_separator_mode(lines, grammar)
  local boundaries = find_boundaries(lines, grammar)
  local db = grammar.db_type

  if #boundaries == 0 then
    return { headers = {}, rows = {}, metadata = { db_type = db } }
  end

  if #boundaries == 1 then
    local chunk = vim.list_slice(lines, math.max(1, boundaries[1] - 1), #lines)
    local parsed = grammar.parse_chunk(chunk)
    return { headers = parsed.headers, rows = parsed.rows, metadata = { db_type = db } }
  end

  -- Multiple separators → multiple result sets
  local result_sets = {}
  for i, sep_idx in ipairs(boundaries) do
    local next_sep_idx = boundaries[i + 1]
    local chunk_end   = next_sep_idx and (next_sep_idx - 2) or #lines
    local chunk = vim.list_slice(lines, math.max(1, sep_idx - 1), chunk_end)
    local parsed = grammar.parse_chunk(chunk)
    table.insert(result_sets, {
      headers  = parsed.headers,
      rows     = parsed.rows,
      metadata = { db_type = db },
    })
  end
  return { multiple_results = true, result_sets = result_sets, metadata = { db_type = db } }
end

-- A + dispatch: entry point — accepts grammar table (new) or db_type string (legacy)
---@param lines string[] Raw CLI output lines
---@param grammar_or_type table|string? Grammar descriptor from a DB module, or legacy db_type string
---@return table {headers, rows, metadata} or {multiple_results, result_sets, metadata}
function M.parse(lines, grammar_or_type)
  if not lines or #lines == 0 then return { headers = {}, rows = {}, metadata = {} } end

  -- New path: grammar table passed directly from DB module's execute_single
  if type(grammar_or_type) == "table" then
    local g = grammar_or_type
    if g.boundary_mode == "footer"    then return parse_footer_mode(lines, g) end
    if g.boundary_mode == "separator" then return parse_separator_mode(lines, g) end
  end

  -- Legacy string path — delegate to named parsers (backward compat)
  if type(grammar_or_type) == "string" then
    local t = grammar_or_type:lower():gsub("[%s%-_]", "")
    if t == "sqlserver" or t == "mssql"     then return M.parse_sqlserver(lines) end
    if t == "sqlite"                         then return M.parse_sqlite(lines) end
    if t == "mysql" or t == "mariadb"       then return M.parse_mysql(lines) end
    if t == "postgres" or t == "postgresql" then return M.parse_postgresql(lines) end
  end

  -- Auto-detect fallback
  local first = table.concat(vim.list_slice(lines, 1, math.min(5, #lines)), "\n")
  if first:match("|") and first:match("%-+|") then return M.parse_sqlserver(lines) end
  if first:match("^%+%-")                     then return M.parse_mysql(lines) end
  if first:match("^%s*%-+%+")                 then return M.parse_postgresql(lines) end
  if first:match("[%-%s]") and first:match("%S") then return M.parse_sqlite(lines) end
  return {
    headers  = { "Result" },
    rows     = vim.tbl_map(function(l) return { l } end, lines),
    metadata = { db_type = "unknown" },
  }
end
-- Thin delegators: load DB module grammar and run through the normalized pipeline
function M.parse_sqlserver(lines)
  if not lines or #lines == 0 then return { headers = {}, rows = {}, metadata = {} } end
  return parse_footer_mode(lines, require("enhance.db.sqlserver").grammar)
end

function M.parse_sqlite(lines)
  if not lines or #lines == 0 then return { headers = {}, rows = {}, metadata = {} } end
  return parse_separator_mode(lines, require("enhance.db.sqlite").grammar)
end

function M.parse_mysql(lines)
  if not lines or #lines == 0 then return { headers = {}, rows = {}, metadata = {} } end
  return parse_footer_mode(lines, require("enhance.db.mysql").grammar)
end

function M.parse_postgresql(lines)
  if not lines or #lines == 0 then return { headers = {}, rows = {}, metadata = {} } end
  return parse_separator_mode(lines, require("enhance.db.postgres").grammar)
end

-- Test aliases (M._function_name pattern)
M._normalize_headers = normalize_headers
M._find_boundaries   = find_boundaries


return M
