-- Default deadlines shared by synchronous and asynchronous structured queries.
local M = {
  connect_seconds = 15,
  command_seconds = 240,
  grace_seconds = 5,
}

---@param opts? { connect_timeout_seconds?: integer, command_timeout_seconds?: integer }
---@return integer
function M.process_ms(opts)
  opts = opts or {}
  return ((opts.connect_timeout_seconds or M.connect_seconds)
    + (opts.command_timeout_seconds or M.command_seconds) + M.grace_seconds) * 1000
end

return M
