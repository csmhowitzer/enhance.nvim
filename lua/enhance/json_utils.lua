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

--- Pretty-print a JSON string, keeping it exactly as written: key order, strings and escapes, number
--- formats. Pure Lua (no jq/python3 process per view, which blocked 60-85 ms each on WSL); jq's layout
--- with two-space indents and empty {} / [] kept on one line. Invalid JSON comes back unchanged.
---@param json_str string Original JSON string
---@return string Formatted JSON string with preserved key order
function M.pretty_print_string(json_str)
  if type(json_str) ~= 'string' or not pcall(vim.json.decode, json_str) then
    return json_str
  end
  local out, depth, i, n = {}, 0, 1, #json_str
  local function newline()
    out[#out + 1] = '\n' .. string.rep('  ', depth)
  end
  while i <= n do
    -- copy everything up to the next structural character, string or whitespace in one go
    local j = json_str:find('[%s"{}%[%],:]', i)
    if not j then
      out[#out + 1] = json_str:sub(i)
      break
    end
    if j > i then out[#out + 1] = json_str:sub(i, j - 1) end
    local c = json_str:sub(j, j)
    if c == '"' then
      -- a string, escapes included, copied verbatim
      local k = j + 1
      while true do
        local q = json_str:find('["\\]', k)
        if not q then k = n; break end
        if json_str:sub(q, q) == '\\' then k = q + 2 else k = q; break end
      end
      out[#out + 1] = json_str:sub(j, k)
      i = k + 1
    elseif c == '{' or c == '[' then
      local close = c == '{' and '}' or ']'
      local next_char = json_str:find('%S', j + 1)
      if next_char and json_str:sub(next_char, next_char) == close then
        out[#out + 1] = c .. close
        i = next_char + 1
      else
        out[#out + 1] = c
        depth = depth + 1
        newline()
        i = j + 1
      end
    elseif c == '}' or c == ']' then
      depth = depth - 1
      newline()
      out[#out + 1] = c
      i = j + 1
    elseif c == ',' then
      out[#out + 1] = ','
      newline()
      i = j + 1
    elseif c == ':' then
      out[#out + 1] = ': '
      i = j + 1
    else
      i = j + 1 -- whitespace between tokens
    end
  end
  return table.concat(out)
end

--- Pretty-print JSON with indentation (DEPRECATED - sorts keys alphabetically)
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

