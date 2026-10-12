-- enhance.nvim - SQL Statement Detector
-- Detects individual statements in a SQL query and their types

local M = {}
local lexer = require('enhance.sql_lexer')

---Statement type keywords
local STATEMENT_KEYWORDS = {
  SELECT = "SELECT",
  INSERT = "INSERT",
  UPDATE = "UPDATE",
  DELETE = "DELETE",
  CREATE = "CREATE",
  DROP = "DROP",
  ALTER = "ALTER",
  PRAGMA = 'PRAGMA',
  SHOW = 'SHOW',
  DESCRIBE = 'DESCRIBE',
  EXPLAIN = 'EXPLAIN',
}

---Detect the type of a SQL statement
---@param text string Statement text
---@return string Statement type (SELECT, INSERT, etc.)
local function detect_statement_type(text)
  local trimmed = vim.trim(lexer.code(text))
  local upper = trimmed:upper()
  
  for keyword, type in pairs(STATEMENT_KEYWORDS) do
    if upper:match("^" .. keyword .. "%s") or upper:match("^" .. keyword .. "$") then
      return type
    end
  end
  
  return "UNKNOWN"
end

---Detect all statements in a SQL query
---@param query string SQL query (may contain multiple statements)
---@return table[] Array of {type: string, text: string} statement objects
function M.detect_statements(query)
  if not query or query == "" then
    return {}
  end

  -- Undelimited SQL stays intact: INSERT...SELECT and UNION are not boundaries.
  local statement_texts = lexer.split(query)

  -- Build statement objects with types
  local statements = {}
  for _, text in ipairs(statement_texts) do
    local _, _, uncertain_keywords = lexer.split(text)
    table.insert(statements, {
      type = detect_statement_type(text),
      text = text,
      requires_batch = uncertain_keywords,
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
    local upper = lexer.code(stmt.text):upper()
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
M._remove_comments = lexer.code
M._split_by_semicolon = lexer.split
M._split_by_keywords = lexer.split
M._contains_transaction_block = M.contains_transaction_block

return M
