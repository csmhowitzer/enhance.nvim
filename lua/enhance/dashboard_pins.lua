-- Persist dashboard pins separately from connection credentials.
local M = {}

local function path(connection)
  return vim.fn.stdpath('data') .. '/enhance.nvim/' .. connection.name .. '/pins.json'
end

---Return pinned table names in the order they were pinned.
---@param connection table Connection to look up
---@return string[]
function M.list(connection)
  local filename = path(connection)
  if vim.fn.filereadable(filename) ~= 1 then return {} end
  local ok, names = pcall(vim.json.decode, table.concat(vim.fn.readfile(filename), '\n'))
  if not ok or type(names) ~= 'table' then return {} end
  local result, seen = {}, {}
  for _, name in ipairs(names) do
    if type(name) == 'string' and name ~= '' and not seen[name] and #result < 8 then
      result[#result + 1] = name
      seen[name] = true
    end
  end
  return result
end

---Whether this table is pinned for the connection.
---@param connection table
---@param name string Full table name, including schema when available
---@return boolean
function M.has(connection, name)
  for _, pinned in ipairs(M.list(connection)) do
    if pinned == name then return true end
  end
  return false
end

---Toggle a pin and save it on disk; return the new state or an error.
---@param connection table
---@param name string
---@return boolean? pinned
---@return string? error
function M.toggle(connection, name)
  local names = M.list(connection)
  local pinned = true
  for i, existing in ipairs(names) do
    if existing == name then
      table.remove(names, i)
      pinned = false
      break
    end
  end
  if pinned then
    if #names >= 8 then return nil, 'You can pin up to 8 tables per connection' end
    names[#names + 1] = name
  end
  local filename = path(connection)
  local dir = vim.fn.fnamemodify(filename, ':h')
  if vim.fn.mkdir(dir, 'p') == 0 and vim.fn.isdirectory(dir) ~= 1 then
    return nil, 'Could not create dashboard pins directory'
  end
  local ok, err = pcall(vim.fn.writefile, { vim.json.encode(names) }, filename)
  if not ok then return nil, tostring(err) end
  return pinned
end

return M
