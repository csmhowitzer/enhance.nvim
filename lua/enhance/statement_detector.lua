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

---Get the SQL keyword starting at position i (uppercase), or nil if not a word start
---@param text string Full query text
---@param i number Position to check
---@return string? word Uppercase keyword or nil
local function get_word_at(text, i)
  local word = text:sub(i):match("^([%a_][%a_%d]*)")
  return word and word:upper() or nil
end

---Check if position i is at a word boundary (preceded by non-identifier character)
---@param text string Full query text
---@param i number Position to check
---@return boolean True if at word boundary
local function at_word_boundary(text, i)
  if i == 1 then return true end
  local prev = text:sub(i - 1, i - 1)
  return prev:match("[^%a_%d]") ~= nil
end

---Split query by semicolons (respecting strings, comments, and BEGIN/END blocks)
---Semicolons inside T-SQL BEGIN...END blocks are NOT treated as statement boundaries.
---@param query string SQL query
---@return string[] Statement texts
local function split_by_semicolon(query)
  local statements = {}
  local current = ""
  local begin_depth = 0

  local i = 1
  while i <= #query do
    local char = query:sub(i, i)
    local in_str = is_inside_string(query, i)
    local in_cmt = is_inside_comment(query, i)

    -- Track BEGIN/END depth for compound T-SQL blocks
    if not in_str and not in_cmt and at_word_boundary(query, i) then
      local word = get_word_at(query, i)
      if word == "BEGIN" then
        -- Skip BEGIN TRANSACTION / BEGIN TRY / BEGIN CATCH (no matching END pair)
        local after_begin = query:sub(i + 5):match("^%s*(%a+)")
        local next_word = after_begin and after_begin:upper() or ""
        if next_word ~= "TRANSACTION" and next_word ~= "TRY" and next_word ~= "CATCH" then
          begin_depth = begin_depth + 1
        end
      elseif word == "END" and begin_depth > 0 then
        begin_depth = begin_depth - 1
      end
    end

    if char == ";" and not in_str and not in_cmt and begin_depth == 0 then
      -- Found a statement boundary outside any BEGIN/END block
      local trimmed = vim.trim(current)
      if trimmed ~= "" then
        table.insert(statements, trimmed)
      end
      current = ""
    else
      current = current .. char
    end

    i = i + 1
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
---Statement keywords inside BEGIN...END blocks are NOT treated as boundaries.
---@param query string SQL query
---@return string[] Statement texts
local function split_by_keywords(query)
  -- Remove comments first to avoid detecting keywords in comments
  local cleaned_query = remove_comments(query)

  local statements = {}
  local current = ""
  local paren_depth = 0
  local begin_depth = 0

  local i = 1
  while i <= #cleaned_query do
    local char = cleaned_query:sub(i, i)
    local in_str = is_inside_string(cleaned_query, i)

    -- Track parentheses depth
    if char == "(" and not in_str then
      paren_depth = paren_depth + 1
    elseif char == ")" and not in_str then
      paren_depth = paren_depth - 1
    end

    -- Track BEGIN/END depth for compound T-SQL blocks
    if not in_str and at_word_boundary(cleaned_query, i) then
      local word = get_word_at(cleaned_query, i)
      if word == "BEGIN" then
        local after_begin = cleaned_query:sub(i + 5):match("^%s*(%a+)")
        local next_word = after_begin and after_begin:upper() or ""
        if next_word ~= "TRANSACTION" and next_word ~= "TRY" and next_word ~= "CATCH" then
          begin_depth = begin_depth + 1
        end
      elseif word == "END" and begin_depth > 0 then
        begin_depth = begin_depth - 1
      end
    end

    -- Check for statement keywords only at paren depth 0 AND begin depth 0
    if paren_depth == 0 and begin_depth == 0 and not in_str then
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

---Check if statements contain a transaction block
---@param statements table[] Array of statement objects
---@return boolean True if transaction block detected
function M.contains_transaction_block(statements)
  if not statements or #statements == 0 then
    return false
  end

  local has_begin = false
  local has_end = false

  for _, stmt in ipairs(statements) do
    local upper = stmt.text:upper()
    local trimmed = vim.trim(upper)

    -- Check for transaction start
    if trimmed:match("^BEGIN") or
       trimmed:match("^START%s+TRANSACTION") or
       trimmed:match("^BEGIN%s+TRANSACTION") then
      has_begin = true
    end

    -- Check for transaction end
    if trimmed:match("^COMMIT") or
       trimmed:match("^ROLLBACK") or
       trimmed:match("^END%s+TRANSACTION") or
       trimmed:match("^END$") then
      has_end = true
    end
  end

  -- Transaction block if we have both begin and end
  return has_begin and has_end
end

-- Expose internal functions for testing
M._detect_statement_type = detect_statement_type
M._is_inside_string = is_inside_string
M._is_inside_comment = is_inside_comment
M._remove_comments = remove_comments
M._split_by_semicolon = split_by_semicolon
M._split_by_keywords = split_by_keywords
M._contains_transaction_block = M.contains_transaction_block
M._get_word_at = get_word_at
M._at_word_boundary = at_word_boundary

return M

