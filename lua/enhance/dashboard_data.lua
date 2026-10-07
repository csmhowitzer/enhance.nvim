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
function M.fetch_sqlserver_rows(connection, callback)
  local adapter = require('enhance.db.sqlserver')
  local cmd = adapter.build_cmd(connection, {
    query = sqlserver_rows_query, metadata = true, no_headers = true,
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
          callback(M.parse_sqlserver_rows(output))
        end
      end)
    end,
  })
  if job <= 0 then
    vim.schedule(function() callback(nil) end)
  end
end

return M
