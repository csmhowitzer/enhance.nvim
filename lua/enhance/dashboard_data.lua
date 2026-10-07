-- Lightweight catalog data for the connected dashboard.
local M = {}

local sqlserver_rows_query = [[
SELECT TOP (8) SCHEMA_NAME(t.schema_id) + '.' + t.name AS table_name,
       SUM(p.rows) AS estimated_rows
FROM sys.tables AS t
JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.is_ms_shipped = 0
GROUP BY t.schema_id, t.name
ORDER BY estimated_rows DESC, table_name;
]]

---Parse catalog rows while ignoring sqlcmd's footer and informational lines.
---@param lines string[]
---@return table[] rows { name: string, count: integer }[]
function M.parse_sqlserver_rows(lines)
  local rows = {}
  for _, line in ipairs(lines) do
    local name, count = line:match('^%s*(.-)%s*|%s*(%d+)%s*$')
    if name and name ~= '' then
      rows[#rows + 1] = { name = name, count = tonumber(count) }
    end
  end
  return rows
end

---Fetch the eight largest SQL Server tables using catalog row estimates.
---Calls back with nil if metadata is unavailable (permissions or CLI failure).
---@param connection table
---@param callback fun(rows: table[]?)
local function fetch_rows(connection, query, callback, parse)
  local adapter = require('enhance.db.sqlserver')
  local cmd = adapter.build_cmd(connection, {
    query = query, metadata = true, no_headers = true,
  })
  table.insert(cmd, #cmd - 1, '-w')
  table.insert(cmd, #cmd - 1, '512')

  local output, errors = {}, {}
  local job = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, lines)
      for _, line in ipairs(lines or {}) do
        if line ~= '' then output[#output + 1] = line end
      end
    end,
    on_stderr = function(_, lines)
      for _, line in ipairs(lines or {}) do
        if line ~= '' then errors[#errors + 1] = line end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 or #errors > 0 or adapter.has_error(output) then
          callback(nil)
        else
          callback((parse or M.parse_sqlserver_rows)(output))
        end
      end)
    end,
  })
  if job <= 0 then
    vim.schedule(function() callback(nil) end)
  end
end

function M.fetch_sqlserver_rows(connection, callback)
  fetch_rows(connection, sqlserver_rows_query, callback)
end

---Parse used data-file space in kB, ignoring sqlcmd's footer.
---@param lines string[]
---@return integer?
function M.parse_database_size(lines)
  for _, line in ipairs(lines) do
    local size = line:match('^%s*(%d+)%s*$')
    if size then return tonumber(size) end
  end
end

---Fetch space used in all of this database's data files (not log files).
---@param connection table
---@param callback fun(size_kb: integer?)
function M.fetch_database_size(connection, callback)
  fetch_rows(connection, [[
SELECT SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint)) * 8 AS data_kb
FROM sys.database_files
WHERE type = 0;
]], callback, M.parse_database_size)
end

---Build a safe catalog predicate for the explorer's bare or schema-qualified names.
---@param names string[]
---@return string
local function pinned_condition(names)
  local literals = {}
  local short_literals = {}
  for _, name in ipairs(names) do
    literals[#literals + 1] = "N'" .. name:gsub("'", "''") .. "'"
    if not name:find('.', 1, true) then
      short_literals[#short_literals + 1] = "N'" .. name:gsub("'", "''") .. "'"
    end
  end
  local condition = "SCHEMA_NAME(t.schema_id) + '.' + t.name IN (" .. table.concat(literals, ', ') .. ')'
  if #short_literals > 0 then
    condition = '(' .. condition .. ' OR t.name IN (' .. table.concat(short_literals, ', ') .. '))'
  end
  return condition
end

---Fetch catalog estimates for up to eight pinned SQL Server tables.
---@param connection table
---@param names string[]
---@param callback fun(rows: table[]?)
function M.fetch_pinned_rows(connection, names, callback)
  if #names == 0 then callback({}); return end
  local query = [[
SELECT SCHEMA_NAME(t.schema_id) + '.' + t.name AS table_name,
       SUM(p.rows) AS estimated_rows
FROM sys.tables AS t
JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.is_ms_shipped = 0
  AND ]] .. pinned_condition(names) .. [[
GROUP BY t.schema_id, t.name
ORDER BY table_name;
]]
  fetch_rows(connection, query, callback)
end

---Parse per-table catalog metrics, ignoring sqlcmd informational output.
---@param lines string[]
---@return table[] {name: string, columns: integer, indexes: integer, data_kb: integer}[]
function M.parse_pinned_details(lines)
  local details = {}
  for _, line in ipairs(lines) do
    local name, columns, indexes, data_kb = line:match('^%s*(.-)%s*|%s*(%d+)%s*|%s*(%d+)%s*|%s*(%d+)%s*$')
    if name and name ~= '' then
      details[#details + 1] = {
        name = name, columns = tonumber(columns), indexes = tonumber(indexes), data_kb = tonumber(data_kb),
      }
    end
  end
  return details
end

---Fetch column, index, and allocated data-page totals in one catalog query.
---Data pages include heap/clustered and LOB allocation, not nonclustered indexes.
---@param connection table
---@param names string[] Pinned table names
---@param callback fun(details: table[]?)
function M.fetch_pinned_details(connection, names, callback)
  if #names == 0 then callback({}); return end
  local query = [[
SELECT SCHEMA_NAME(t.schema_id) + '.' + t.name AS table_name,
       (SELECT COUNT(*) FROM sys.columns AS c WHERE c.object_id = t.object_id) AS column_count,
       (SELECT COUNT(*) FROM sys.indexes AS i
        WHERE i.object_id = t.object_id AND i.index_id > 0 AND i.is_hypothetical = 0) AS index_count,
       COALESCE((SELECT SUM(CAST(a.total_pages AS bigint)) * 8
                 FROM sys.partitions AS p
                 JOIN sys.allocation_units AS a ON
                   (a.type IN (1, 3) AND a.container_id = p.hobt_id)
                   OR (a.type = 2 AND a.container_id = p.partition_id)
                 WHERE p.object_id = t.object_id AND p.index_id IN (0, 1)), 0) AS data_kb
FROM sys.tables AS t
WHERE t.is_ms_shipped = 0
  AND ]] .. pinned_condition(names) .. [[
ORDER BY table_name;
]]
  fetch_rows(connection, query, callback, M.parse_pinned_details)
end

return M
