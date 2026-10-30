-- Per-buffer results data (row map, sections, line numbers, parsed result, JSON columns), kept in Lua.
-- Buffer variables copy the whole value on every read and write; for row maps whose entries share the
-- rows/headers tables that made displaying 1,000 rows take seconds and 3,000 rows tens of seconds.

local M = {}

---@type table<integer, table<string, any>>
local by_buf = {}

local augroup

---@param bufnr integer
local function watch(bufnr)
  augroup = augroup or vim.api.nvim_create_augroup('EnhanceResultState', { clear = true })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = augroup,
    buffer = bufnr,
    once = true,
    callback = function()
      by_buf[bufnr] = nil
    end,
  })
end

---@param bufnr integer
---@param key string
---@return any
function M.get(bufnr, key)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local state = by_buf[bufnr]
  return state and state[key]
end

---@param bufnr integer
---@param key string
---@param value any
function M.set(bufnr, key, value)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local state = by_buf[bufnr]
  if not state then
    if value == nil then
      return
    end
    state = {}
    by_buf[bufnr] = state
    watch(bufnr)
  end
  state[key] = value
end

return M
