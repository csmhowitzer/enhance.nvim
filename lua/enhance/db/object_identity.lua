-- Parse explorer object labels and quote their components for SQL.
local M = {}

local function dialect(db_type)
  if db_type == 'sqlserver' or db_type == 'mssql' then return '[', ']' end
  if db_type == 'mysql' or db_type == 'mariadb' then return '`', '`' end
  return '"', '"'
end

---Split a displayed name at dots outside quoted identifiers.
---@param label string
---@param db_type string
---@return string? schema
---@return string name
function M.parts(label, db_type)
  local opener, closer = dialect(db_type)
  local fields, part, index, quoted = {}, {}, 1, false
  while index <= #label do
    local char = label:sub(index, index)
    if quoted and char == closer and label:sub(index + 1, index + 1) == closer then
      part[#part + 1] = closer
      index = index + 2
    elseif quoted and char == closer then
      quoted = false
      index = index + 1
    elseif not quoted and char == opener and #part == 0 then
      quoted = true
      index = index + 1
    elseif not quoted and char == '.' and db_type ~= 'sqlite' then
      fields[#fields + 1] = table.concat(part)
      part = {}
      index = index + 1
    else
      part[#part + 1] = char
      index = index + 1
    end
  end
  fields[#fields + 1] = table.concat(part)
  if #fields == 2 then return fields[1], fields[2] end
  if #fields == 1 then return nil, fields[1] end
  return nil, label
end

---@param value string
---@param db_type string
---@return string
function M.quote(value, db_type)
  local opener, closer = dialect(db_type)
  return opener .. value:gsub(closer, closer .. closer) .. closer
end

---@param schema string?
---@param name string
---@param db_type string
---@return string
function M.label(schema, name, db_type)
  local quoted = M.quote(name, db_type)
  return schema and M.quote(schema, db_type) .. '.' .. quoted or quoted
end

---@param label string
---@param db_type string
---@return string
---@return string?
---@return string
function M.sql(label, db_type)
  local schema, name = M.parts(label, db_type)
  if not schema and (db_type == 'sqlserver' or db_type == 'mssql') then schema = 'dbo' end
  return M.label(schema, name, db_type), schema, name
end

---@param value string
---@param db_type string
---@return string
function M.literal(value, db_type)
  local prefix = (db_type == 'sqlserver' or db_type == 'mssql') and 'N' or ''
  return prefix .. "'" .. value:gsub("'", "''") .. "'"
end

return M
