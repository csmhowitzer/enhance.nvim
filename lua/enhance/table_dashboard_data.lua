-- SQL Server catalog lookups for a single table's dashboard.
local M = {}

local function literal(value)
  return "N'" .. value:gsub("'", "''") .. "'"
end

local function table_id(name)
  local schema, bare = name:match('^([^.]+)%.(.+)$')
  local condition = schema and 'SCHEMA_NAME(t.schema_id) = ' .. literal(schema)
    .. ' AND t.name = ' .. literal(bare) or 't.name = ' .. literal(name)
  return '(SELECT TOP (1) t.object_id FROM sys.tables AS t WHERE t.is_ms_shipped = 0 AND '
    .. condition .. " ORDER BY CASE WHEN SCHEMA_NAME(t.schema_id) = 'dbo' THEN 0 ELSE 1 END, t.schema_id)"
end

local function run(connection, query, callback, definition)
  local adapter = require('enhance.db.sqlserver')
  local cmd = adapter.build_cmd(connection, { query = query, no_headers = true, metadata = not definition })
  table.insert(cmd, #cmd - 1, '-w')
  table.insert(cmd, #cmd - 1, definition and '65535' or '4096')
  local output, errors = {}, {}
  local job = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, lines)
      for _, line in ipairs(lines or {}) do output[#output + 1] = line end
    end,
    on_stderr = function(_, lines)
      for _, line in ipairs(lines or {}) do
        if line ~= '' then errors[#errors + 1] = line end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        callback(code == 0 and #errors == 0 and not adapter.has_error(output) and output or nil)
      end)
    end,
  })
  if job <= 0 then vim.schedule(function() callback(nil) end) end
end

---@param connection table
---@param name string Bare or schema-qualified table name
---@param callback fun(script: string?)
function M.fetch_create_script(connection, name, callback)
  local query = [[
SELECT SCHEMA_NAME(t.schema_id) + '|' + t.name + '|' + c.name + '|' +
       TYPE_NAME(c.user_type_id) + '|' + CAST(c.max_length AS varchar(10)) + '|' +
       CAST(c.precision AS varchar(10)) + '|' + CAST(c.scale AS varchar(10)) + '|' +
       CAST(c.is_nullable AS varchar(1)) + '|' +
       COALESCE(CAST(ic.seed_value AS varchar(30)), '') + '|' +
       COALESCE(CAST(ic.increment_value AS varchar(30)), '') + '|' +
       CAST(COALESCE((SELECT ix.key_ordinal FROM sys.indexes AS i
         JOIN sys.index_columns AS ix ON ix.object_id = i.object_id AND ix.index_id = i.index_id
         WHERE i.object_id = t.object_id AND i.is_primary_key = 1
           AND ix.column_id = c.column_id AND ix.key_ordinal > 0), 0) AS varchar(10)) + '|' +
       COALESCE(dc.definition, '') + '|' + COALESCE(cc.definition, '')
FROM sys.tables AS t
JOIN sys.columns AS c ON c.object_id = t.object_id
LEFT JOIN sys.identity_columns AS ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id
LEFT JOIN sys.default_constraints AS dc ON dc.object_id = c.default_object_id
LEFT JOIN sys.computed_columns AS cc ON cc.object_id = c.object_id AND cc.column_id = c.column_id
WHERE t.object_id = ]] .. table_id(name) .. [[
ORDER BY c.column_id;
]]
  run(connection, query, function(lines)
    if not lines then callback(nil); return end
    callback(M.parse_create_script(lines))
  end)
end

local function bracket(value)
  return '[' .. value:gsub(']', ']]') .. ']'
end

---@param lines string[]
---@return string?
function M.parse_create_script(lines)
  local columns, keys, schema, name = {}, {}, nil, nil
  for _, line in ipairs(lines) do
    local parts = vim.split(line, '|', { plain = true, trimempty = false })
    if #parts >= 13 and tonumber(parts[5]) and tonumber(parts[11]) then
      schema, name = vim.trim(parts[1]), vim.trim(parts[2])
      local col, datatype = bracket(vim.trim(parts[3])), vim.trim(parts[4])
      local length, precision, scale = tonumber(parts[5]), tonumber(parts[6]), tonumber(parts[7])
      if datatype == 'nvarchar' or datatype == 'nchar' then
        datatype = datatype .. '(' .. (length == -1 and 'MAX' or tostring(length / 2)) .. ')'
      elseif datatype == 'varchar' or datatype == 'char' or datatype == 'varbinary' or datatype == 'binary' then
        datatype = datatype .. '(' .. (length == -1 and 'MAX' or tostring(length)) .. ')'
      elseif datatype == 'decimal' or datatype == 'numeric' then
        datatype = string.format('%s(%d, %d)', datatype, precision, scale)
      elseif datatype == 'datetime2' or datatype == 'datetimeoffset' or datatype == 'time' then
        datatype = string.format('%s(%d)', datatype, scale)
      end
      local computed = vim.trim(parts[13])
      local definition = col .. (computed ~= '' and ' AS ' .. computed or ' ' .. datatype)
      local seed, increment = vim.trim(parts[9]), vim.trim(parts[10])
      if seed ~= '' and computed == '' then definition = definition .. ' IDENTITY(' .. seed .. ', ' .. increment .. ')' end
      local default = vim.trim(parts[12])
      if default ~= '' and computed == '' then definition = definition .. ' DEFAULT ' .. default end
      if parts[8] == '0' and computed == '' then definition = definition .. ' NOT NULL' end
      columns[#columns + 1] = '    ' .. definition
      local ordinal = tonumber(parts[11])
      if ordinal > 0 then keys[#keys + 1] = { ordinal = ordinal, name = col } end
    end
  end
  if not name then return nil end
  table.sort(keys, function(a, b) return a.ordinal < b.ordinal end)
  if #keys > 0 then
    local names = {}
    for _, key in ipairs(keys) do names[#names + 1] = key.name end
    columns[#columns + 1] = '    PRIMARY KEY (' .. table.concat(names, ', ') .. ')'
  end
  return 'CREATE TABLE ' .. bracket(schema) .. '.' .. bracket(name) .. ' (\n'
    .. table.concat(columns, ',\n') .. '\n);'
end

---@param connection table
---@param name string
---@param callback fun(refs: table[]?)
function M.fetch_references(connection, name, callback)
  local query = [[
SELECT DISTINCT CASE WHEN o.type = 'V' THEN 'View'
       WHEN o.type IN ('P', 'PC', 'X') THEN 'Procedure' ELSE 'Function' END + '|' +
       SCHEMA_NAME(o.schema_id) + '.' + o.name
FROM sys.sql_expression_dependencies AS d
JOIN sys.objects AS o ON o.object_id = d.referencing_id
WHERE o.type IN ('V', 'P', 'PC', 'X', 'FN', 'IF', 'TF', 'FS', 'FT')
  AND d.referenced_id = ]] .. table_id(name) .. [[
ORDER BY 1;
]]
  run(connection, query, function(lines)
    if not lines then callback(nil); return end
    local refs = {}
    for _, line in ipairs(lines) do
      local kind, object = line:match('^%s*([^|]+)|(.+)%s*$')
      if (kind == 'View' or kind == 'Procedure' or kind == 'Function') and object then
        refs[#refs + 1] = { kind = kind, name = vim.trim(object) }
      end
    end
    callback(refs)
  end)
end

---@param paths string[] Saved .sql filepaths
---@param name string
---@return table[]
function M.saved_references(paths, name)
  local schema, bare = name:match('^([^.]+)%.(.+)$')
  bare = bare or name
  local refs = {}
  for _, path in ipairs(paths) do
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok then
      local sql = table.concat(lines, '\n'):lower():gsub('/%*.-%*/', ''):gsub('%-%-[^\n]*', '')
      local needle = bare:lower()
      local start = 1
      while true do
        local from, to = sql:find(needle, start, true)
        if not from then break end
        local before, after = sql:sub(from - 1, from - 1), sql:sub(to + 1, to + 1)
        local qualifier = sql:sub(1, from - 1):match('([%w_]+)%.$')
        if not before:match('[%w_]') and not after:match('[%w_]')
          and (not schema or not qualifier or qualifier == schema:lower()) then
          refs[#refs + 1] = { kind = 'Saved Query', name = vim.fn.fnamemodify(path, ':t'), path = path }
          break
        end
        start = to + 1
      end
    end
  end
  return refs
end

---@param connection table
---@param name string
---@param callback fun(definition: string?)
function M.fetch_definition(connection, name, callback)
  run(connection, 'SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('
    .. literal(name) .. ');', function(lines)
    if not lines then callback(nil); return end
    local content = {}
    for _, line in ipairs(lines) do
      if not line:match('^%(%d+ rows? affected%)') then
        content[#content + 1] = line:gsub('%s+$', '')
      end
    end
    while content[1] == '' do table.remove(content, 1) end
    while content[#content] == '' do table.remove(content) end
    callback(#content > 0 and table.concat(content, '\n') or nil)
  end, true)
end

return M
