-- Lexical boundaries only: never infer a statement boundary from SQL keywords.
local M = {}

---Scan SQL once, retaining source positions and masking comments for classification.
---@param sql string
---@return table[] tokens
---@return string code SQL with comments replaced by whitespace
local function scan(sql)
  local tokens, code = {}, {}
  local i = 1
  while i <= #sql do
    local char, pair = sql:sub(i, i), sql:sub(i, i + 1)
    local start = i
    if pair == '--' or pair == '/*' then
      if pair == '--' then
        i = sql:find('\n', i + 2, true) or (#sql + 1)
      else
        local depth = 1
        i = i + 2
        while i <= #sql and depth > 0 do
          pair = sql:sub(i, i + 1)
          if pair == '/*' then depth = depth + 1; i = i + 2
          elseif pair == '*/' then depth = depth - 1; i = i + 2
          else i = i + 1 end
        end
      end
      code[#code + 1] = sql:sub(start, i - 1):gsub('[^\r\n]', ' ')
    elseif char == "'" or char == '"' or char == '[' or char == '`' then
      local close = char == '[' and ']' or char
      i = i + 1
      while i <= #sql do
        if sql:sub(i, i) == close then
          if sql:sub(i + 1, i + 1) == close then i = i + 2
          else i = i + 1; break end
        else i = i + 1 end
      end
      code[#code + 1] = sql:sub(start, i - 1)
    elseif char:match('[%a_]') then
      i = i + 1
      while i <= #sql and sql:sub(i, i):match('[%w_$]') do i = i + 1 end
      local word = sql:sub(start, i - 1)
      tokens[#tokens + 1] = { word = word:upper(), pos = start }
      code[#code + 1] = word
    else
      if char == ';' then tokens[#tokens + 1] = { word = ';', pos = i } end
      code[#code + 1] = char
      i = i + 1
    end
  end
  return tokens, table.concat(code)
end

---Return SQL without comments, retaining literals and token separation.
---@param sql string
---@return string
function M.code(sql)
  local _, code = scan(sql)
  return code
end

---Split only at explicit semicolons outside strings/comments/compound blocks.
---@param sql string
---@return string[]
---@return boolean has_boundary
---@return boolean uncertain_keywords
function M.split(sql)
  local tokens = scan(sql)
  local statements, stack = {}, {}
  local start = 1
  local has_boundary = false
  local keyword_count = 0
  local starts = { SELECT = true, INSERT = true, UPDATE = true, DELETE = true,
    CREATE = true, DROP = true, ALTER = true, MERGE = true }
  local function append(last)
    local text = vim.trim(sql:sub(start, last))
    if vim.trim(M.code(text)) ~= '' then statements[#statements + 1] = text end
  end
  for index, token in ipairs(tokens) do
    local word = token.word
    if starts[word] then keyword_count = keyword_count + 1 end
    local following = tokens[index + 1] and tokens[index + 1].word
    if word == 'CASE' then
      stack[#stack + 1] = 'CASE'
    elseif word == 'BEGIN' then
      -- Transactions are session-dependent, not compound BEGIN...END blocks.
      if following ~= 'TRAN' and following ~= 'TRANSACTION' and following ~= 'WORK'
        and following ~= ';' then
        stack[#stack + 1] = 'BEGIN'
      end
    elseif word == 'END' then
      stack[#stack] = nil
    elseif word == ';' and #stack == 0 then
      has_boundary = true
      append(token.pos - 1)
      start = token.pos + 1
    end
  end
  append(#sql)
  return statements, has_boundary, keyword_count > 1
end

return M
