-- enhance.nvim - JSON Utilities
-- Detect and parse JSON strings in database results

local M = {}

--- Check if a string contains valid JSON
---@param str string The string to check
---@return boolean true if valid JSON, false otherwise
function M.is_json(str)
  if not str or type(str) ~= "string" then
    return false
  end
  
  -- Trim whitespace
  str = vim.trim(str)
  
  -- Quick pattern check - must start/end with {} or []
  if not (str:match("^%s*{.*}%s*$") or str:match("^%s*%[.*%]%s*$")) then
    return false
  end
  
  -- Try to parse with vim.json.decode
  local ok, _ = pcall(vim.json.decode, str)
  return ok
end

--- Read string and detect if it's JSON, return parsed result if valid
---@param str string The string to check and parse
---@return boolean is_json Whether the string is valid JSON
---@return any|nil parsed The parsed JSON data, or nil if invalid
function M.parse_if_json(str)
  if not M.is_json(str) then
    return false, nil
  end
  
  local ok, parsed = pcall(vim.json.decode, str)
  return ok, ok and parsed or nil
end

--- Pretty-print JSON with indentation
---@param data any JSON data (table/array)
---@param indent? number Initial indentation level (default: 0)
---@return string Formatted JSON string
function M.pretty_print(data, indent)
  indent = indent or 0
  local indent_str = string.rep("  ", indent)
  
  if type(data) == "table" then
    -- Check if it's an array or object
    local is_array = #data > 0
    
    if is_array then
      local lines = { "[" }
      for i, value in ipairs(data) do
        local formatted = M.pretty_print(value, indent + 1)
        local comma = i < #data and "," or ""
        table.insert(lines, indent_str .. "  " .. formatted .. comma)
      end
      table.insert(lines, indent_str .. "]")
      return table.concat(lines, "\n")
    else
      local lines = { "{" }
      local keys = vim.tbl_keys(data)
      table.sort(keys)
      for i, key in ipairs(keys) do
        local value = data[key]
        local formatted = M.pretty_print(value, indent + 1)
        local comma = i < #keys and "," or ""
        table.insert(lines, string.format('%s  "%s": %s%s', indent_str, key, formatted, comma))
      end
      table.insert(lines, indent_str .. "}")
      return table.concat(lines, "\n")
    end
  elseif type(data) == "string" then
    return string.format('"%s"', data)
  elseif type(data) == "boolean" or type(data) == "number" then
    return tostring(data)
  elseif data == nil then
    return "null"
  else
    return tostring(data)
  end
end

-- Expose internal functions for testing
M._is_json = M.is_json
M._parse_if_json = M.parse_if_json
M._pretty_print = M.pretty_print

return M

