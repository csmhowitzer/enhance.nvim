-- enhance.nvim - Result Formatter
-- Formats parsed database results into consistent table display

local M = {}

---Default formatting configuration
---@class FormatterConfig
---@field max_column_width number Maximum width for any column (default: 50)
---@field min_column_width number Minimum width for any column (default: 3)
---@field null_display string How to display NULL values (default: "NULL")
---@field truncate_indicator string Indicator for truncated values (default: "...")
---@field separator string Column separator (default: " | ")
---@field header_separator_char string Character for header separator line (default: "-")

---@type FormatterConfig
local default_config = {
  max_column_width = 50,
  min_column_width = 3,
  null_display = "NULL",
  truncate_indicator = "...",
  separator = " | ",
  header_separator_char = "-",
}

---Calculate optimal column widths based on data
---@param headers string[] Column headers
---@param rows string[][] Data rows
---@param config FormatterConfig Configuration
---@return number[] Column widths
local function calculate_column_widths(headers, rows, config)
  local widths = {}
  
  -- Initialize with header widths
  for i, header in ipairs(headers) do
    widths[i] = #header
  end
  
  -- Check data rows for wider values
  for _, row in ipairs(rows) do
    for i, cell in ipairs(row) do
      if widths[i] then
        local cell_width = #tostring(cell)
        if cell_width > widths[i] then
          widths[i] = cell_width
        end
      end
    end
  end
  
  -- Apply min/max constraints
  for i = 1, #widths do
    widths[i] = math.max(config.min_column_width, math.min(config.max_column_width, widths[i]))
  end
  
  return widths
end

---Truncate a value to fit within width
---@param value string Value to truncate
---@param width number Target width
---@param indicator string Truncation indicator
---@return string Truncated value
local function truncate_value(value, width, indicator)
  if #value <= width then
    return value
  end
  
  local indicator_len = #indicator
  if width <= indicator_len then
    return indicator:sub(1, width)
  end
  
  return value:sub(1, width - indicator_len) .. indicator
end

---Pad a value to fit within width
---@param value string Value to pad
---@param width number Target width
---@return string Padded value
local function pad_value(value, width)
  local padding = width - #value
  if padding <= 0 then
    return value
  end
  return value .. string.rep(" ", padding)
end

---Format a single row
---@param row string[] Row data
---@param widths number[] Column widths
---@param config FormatterConfig Configuration
---@return string Formatted row
local function format_row(row, widths, config)
  local cells = {}

  -- Iterate over all columns (based on widths, not row length)
  for i = 1, #widths do
    local width = widths[i] or config.min_column_width
    local cell = row[i]

    -- Check for NULL: nil or empty string
    local value
    if cell == nil or cell == "" then
      value = config.null_display
    else
      value = cell
    end

    -- Truncate if needed
    local truncated = truncate_value(tostring(value), width, config.truncate_indicator)

    -- Pad to width
    local padded = pad_value(truncated, width)

    table.insert(cells, padded)
  end

  -- Build row with separators, trim trailing space
  local row = config.separator .. table.concat(cells, config.separator) .. config.separator
  return vim.trim(row)
end

---Generate header separator line
---@param widths number[] Column widths
---@param config FormatterConfig Configuration
---@return string Separator line
local function generate_separator(widths, config)
  local segments = {}
  
  for _, width in ipairs(widths) do
    table.insert(segments, string.rep(config.header_separator_char, width))
  end

  -- Build separator with pipes, trim trailing space
  local separator = config.separator .. table.concat(segments, config.separator) .. config.separator
  return vim.trim(separator)
end

---Format parsed result into table lines
---@param parsed_result table Parsed result from parser {headers, rows, metadata}
---@param user_config FormatterConfig? User configuration overrides
---@return string[] Formatted lines
function M.format(parsed_result, user_config)
  -- Merge config
  local config = vim.tbl_deep_extend("force", default_config, user_config or {})

  local headers = parsed_result.headers or {}
  local rows = parsed_result.rows or {}

  -- Handle empty results
  if #headers == 0 then
    return { "No results" }
  end

  -- Calculate column widths
  local widths = calculate_column_widths(headers, rows, config)

  local lines = {}

  -- Format header
  table.insert(lines, format_row(headers, widths, config))

  -- Add separator
  table.insert(lines, generate_separator(widths, config))

  -- Format data rows
  for _, row in ipairs(rows) do
    table.insert(lines, format_row(row, widths, config))
  end

  return lines
end

---Format a single statement result
---@param statement table Statement Result Object
---@param statement_num number Statement number (1-based)
---@param total_statements number Total number of statements
---@param user_config FormatterConfig? User configuration overrides
---@return string[] Formatted lines
local function format_single_statement(statement, statement_num, total_statements, user_config)
  local lines = {}

  -- Add "Result Set X/Y" header if multiple statements
  if total_statements > 1 then
    table.insert(lines, string.format("Result Set %d/%d", statement_num, total_statements))
    table.insert(lines, "")
  end

  -- Format based on statement type
  if statement.result_table then
    -- SELECT: format table
    local table_lines = M.format(
      { headers = statement.result_table.headers, rows = statement.result_table.rows },
      user_config
    )
    for _, line in ipairs(table_lines) do
      table.insert(lines, line)
    end
  elseif statement.message then
    -- INSERT/UPDATE/DELETE/CREATE/DROP/ALTER: show message
    table.insert(lines, statement.message)
  end

  -- Add status line with execution time
  local status_parts = {}
  if statement.rows then
    local plural = statement.rows == 1 and "row" or "rows"
    table.insert(status_parts, string.format("%d %s", statement.rows, plural))
  end
  if statement.elapsed then
    table.insert(status_parts, string.format("%.2f ms", statement.elapsed))
  end
  if #status_parts > 0 then
    table.insert(lines, "(" .. table.concat(status_parts, ", ") .. ")")
  end

  return lines
end

---Format multiple statement results
---@param statements table[] Array of Statement Result Objects
---@param user_config FormatterConfig? User configuration overrides
---@return string[] Formatted lines
function M.format_multiple_statements(statements, user_config)
  local all_lines = {}

  for i, statement in ipairs(statements) do
    local statement_lines = format_single_statement(statement, i, #statements, user_config)

    -- Add statement lines
    for _, line in ipairs(statement_lines) do
      table.insert(all_lines, line)
    end

    -- Add blank line separator between statements (except after last)
    if i < #statements then
      table.insert(all_lines, "")
    end
  end

  return all_lines
end

-- Expose internal functions for testing
M._calculate_column_widths = calculate_column_widths
M._truncate_value = truncate_value
M._pad_value = pad_value
M._format_row = format_row
M._generate_separator = generate_separator
M._format_single_statement = format_single_statement

return M

