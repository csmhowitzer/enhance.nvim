-- enhance.nvim - SQL Statement Detector
-- Detects individual statements in a SQL query and their types

local M = {}

---Statement type keywords
local STATEMENT_KEYWORDS = {
  SELECT = "SELECT",
  INSERT = "INSERT",
  UPDATE = "UPDATE",
  DELETE = "DELETE",
  CREATE = "CREATE",
  DROP = "DROP",
  ALTER = "ALTER",
}

---Detect the type of a SQL statement
---@param text string Statement text
---@return string Statement type (SELECT, INSERT, etc.)
local function detect_statement_type(text)
  local trimmed = vim.trim(text)
  local upper = trimmed:upper()
  
  for keyword, type in pairs(STATEMENT_KEYWORDS) do
    if upper:match("^" .. keyword .. "%s") or upper:match("^" .. keyword .. "$") then
      return type
    end
  end
  
  return "UNKNOWN"
end

---Check if character is inside a string literal
---@param text string Full text
---@param pos number Position to check
---@return boolean True if inside string
local function is_inside_string(text, pos)
  local in_single_quote = false
  local in_double_quote = false
  
  for i = 1, pos - 1 do
    local char = text:sub(i, i)
    local prev_char = i > 1 and text:sub(i - 1, i - 1) or ""
    
    -- Handle escaped quotes
    if prev_char ~= "\\" then
      if char == "'" then
        in_single_quote = not in_single_quote
      elseif char == '"' then
        in_double_quote = not in_double_quote
      end
    end
  end
  
  return in_single_quote or in_double_quote
end

---Check if position is inside a comment
---@param text string Full text
---@param pos number Position to check
---@return boolean True if inside comment
local function is_inside_comment(text, pos)
  -- Find the line containing this position
  local line_start = 1
  for i = pos, 1, -1 do
    if text:sub(i, i) == "\n" then
      line_start = i + 1
      break
    end
  end
  
  local line_end = #text
  for i = pos, #text do
    if text:sub(i, i) == "\n" then
      line_end = i - 1
      break
    end
  end
  
  local line = text:sub(line_start, line_end)
  local pos_in_line = pos - line_start + 1
  
  -- Check for -- comment
  local comment_start = line:find("%-%-")
  if comment_start and pos_in_line >= comment_start then
    return true
  end
  
  return false
end

---Split query by semicolons (respecting strings and comments)
---@param query string SQL query
---@return string[] Statement texts
local function split_by_semicolon(query)
  local statements = {}
  local current = ""
  
  for i = 1, #query do
    local char = query:sub(i, i)
    
    if char == ";" and not is_inside_string(query, i) and not is_inside_comment(query, i) then
      -- Found a statement boundary
      local trimmed = vim.trim(current)
      if trimmed ~= "" then
        table.insert(statements, trimmed)
      end
      current = ""
    else
      current = current .. char
    end
  end
  
  -- Add remaining statement
  local trimmed = vim.trim(current)
  if trimmed ~= "" then
    table.insert(statements, trimmed)
  end
  
  return statements
end

---Remove SQL comments from query
---@param query string SQL query
---@return string Query without comments
local function remove_comments(query)
  local lines = vim.split(query, "\n")
  local cleaned_lines = {}

  for _, line in ipairs(lines) do
    -- Find -- comment and remove everything after it
    local comment_pos = line:find("%-%-")
    if comment_pos then
      -- Check if -- is inside a string
      local in_string = false
      for i = 1, comment_pos - 1 do
        local char = line:sub(i, i)
        if char == "'" or char == '"' then
          in_string = not in_string
        end
      end

      if not in_string then
        line = line:sub(1, comment_pos - 1)
      end
    end

    table.insert(cleaned_lines, line)
  end

  return table.concat(cleaned_lines, "\n")
end

---Split query by keywords (for SQL Server style without semicolons)
---@param query string SQL query
---@return string[] Statement texts
local function split_by_keywords(query)
  -- Remove comments first to avoid detecting keywords in comments
  local cleaned_query = remove_comments(query)

  local statements = {}
  local current = ""
  local paren_depth = 0

  local i = 1
  while i <= #cleaned_query do
    local char = cleaned_query:sub(i, i)

    -- Track parentheses depth
    if char == "(" and not is_inside_string(cleaned_query, i) then
      paren_depth = paren_depth + 1
    elseif char == ")" and not is_inside_string(cleaned_query, i) then
      paren_depth = paren_depth - 1
    end

    -- Check for statement keywords at depth 0
    if paren_depth == 0 and not is_inside_string(cleaned_query, i) then
      for keyword, _ in pairs(STATEMENT_KEYWORDS) do
        local keyword_len = #keyword
        local potential_keyword = cleaned_query:sub(i, i + keyword_len - 1):upper()

        if potential_keyword == keyword then
          -- Check if it's a word boundary (not part of another word)
          local after_char = cleaned_query:sub(i + keyword_len, i + keyword_len)
          if after_char:match("%s") or after_char == "" or after_char == "(" then
            -- Found a new statement keyword
            if current ~= "" then
              local trimmed = vim.trim(current)
              if trimmed ~= "" then
                table.insert(statements, trimmed)
              end
              current = ""
            end
            break
          end
        end
      end
    end

    current = current .. char
    i = i + 1
  end

  -- Add remaining statement
  local trimmed = vim.trim(current)
  if trimmed ~= "" then
    table.insert(statements, trimmed)
  end

  return statements
end

---Detect all statements in a SQL query
---@param query string SQL query (may contain multiple statements)
---@return table[] Array of {type: string, text: string} statement objects
function M.detect_statements(query)
  if not query or query == "" then
    return {}
  end
  
  local statement_texts = {}
  
  -- Try semicolon-first approach
  if query:find(";") then
    statement_texts = split_by_semicolon(query)
  else
    -- Fallback to keyword detection (SQL Server style)
    statement_texts = split_by_keywords(query)
  end
  
  -- Build statement objects with types
  local statements = {}
  for _, text in ipairs(statement_texts) do
    table.insert(statements, {
      type = detect_statement_type(text),
      text = text,
    })
  end
  
  return statements
end

-- Expose internal functions for testing
M._detect_statement_type = detect_statement_type
M._is_inside_string = is_inside_string
M._is_inside_comment = is_inside_comment
M._remove_comments = remove_comments
M._split_by_semicolon = split_by_semicolon
M._split_by_keywords = split_by_keywords

return M

