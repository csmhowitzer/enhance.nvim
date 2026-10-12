-- Compatibility adapter for explicit synchronous calls, not interactive query execution.
local M = {}

---@param db string Canonical helper backend
---@param connection table
---@param query string Unchanged SQL
---@return EnhanceHelperParsedResult? parsed
---@return string? error
---@return number duration_ms
---@return number returned_rows
function M.execute(db, connection, query)
  local started = (vim.uv or vim.loop).hrtime()
  local function failure(message)
    return nil, message, ((vim.uv or vim.loop).hrtime() - started) / 1000000, 0
  end
  local adapter = require('enhance.db.sqlserver_helper')
  local body, err = adapter.encode_request(vim.tbl_extend('force', connection, { type = db }), query)
  if not body then return failure(err) end
  local resolved, path = pcall(require('enhance.helper_install').path, db)
  if not resolved or not path then return failure('Structured helper unavailable; rebuild enhance.nvim in lazy.nvim') end
  local ok, output = pcall(function()
    return vim.system({ path }, { stdin = body, text = false, stderr = false, timeout = 50000 }):wait()
  end)
  if not ok or (output.signal ~= 0 and output.signal ~= nil) then return failure('Structured helper execution failed') end
  local response, decode_error = adapter.decode_response(output.stdout, output.code, db)
  if not response then return failure(decode_error) end
  local parsed, rows = response.parsed_result, 0
  for _, result in ipairs(parsed.multiple_results and parsed.result_sets or { parsed }) do rows = rows + #result.rows end
  parsed.metadata.affected_rows = response.affected_rows
  parsed.metadata.is_error = not response.ok
  parsed.metadata.errors, parsed.metadata.messages = response.errors, response.messages
  if not response.ok then
    local messages = {}
    for _, diagnostic in ipairs(response.errors) do messages[#messages + 1] = diagnostic.message end
    return parsed, table.concat(messages, '\n'), response.duration_ms, rows
  end
  return parsed, nil, response.duration_ms, rows
end

return M
