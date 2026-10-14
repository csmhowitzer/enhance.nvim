-- Asynchronous process runner used by SQL Server query execution.
local M = {}

---@class EnhanceHelperRunOptions: EnhanceHelperTimeouts
---@field process_timeout_ms integer? Total process deadline; default connect + command + 5 seconds

---@alias EnhanceHelperCallback fun(response: EnhanceHelperDecodedResponse?, error: string?)

---@class EnhanceHelperRunnerDependencies
---@field resolve fun(): string?, string? Offline verified cache lookup, never install
---@field spawn fun(cmd: string[], opts: table, callback: function): vim.SystemObj
---@field schedule fun(callback: function)

---@class EnhanceHelperOperation
---@field callback EnhanceHelperCallback
---@field process vim.SystemObj?
---@field completed boolean
---@field queued boolean
---@field cancelled boolean
---@field response EnhanceHelperDecodedResponse?
---@field error string?

---@class EnhanceHelperRunner
---@field private active EnhanceHelperOperation?
---@field private deps EnhanceHelperRunnerDependencies
local Runner = {}
Runner.__index = Runner

local function stop(operation)
  if not operation.completed and operation.process then
    -- Cancellation is process termination, not SQL replay or a driver transaction command.
    -- KILL avoids leaving a hung helper alive after the UI relinquishes ownership.
    pcall(operation.process.kill, operation.process, 'sigkill')
  end
end

---@param operation EnhanceHelperOperation
local function deliver(self, operation)
  if operation.queued then return end
  operation.queued = true
  self.deps.schedule(function()
    if self.active ~= operation then return end
    -- Relinquish ownership BEFORE calling user code, which may run another query.
    self.active = nil
    operation.callback(operation.response, operation.error)
  end)
end

---Terminate the owned request and deliver one scheduled cancellation.
---Also overrides an exited result that has not yet reached its scheduled callback.
---@return boolean cancelled False if idle or already cancelled
function Runner:cancel()
  local operation = self.active
  if not operation or operation.cancelled then return false end
  operation.cancelled = true
  operation.response, operation.error = nil, (operation.label or 'SQL Server') .. ' helper cancelled'
  stop(operation)
  operation.completed = true
  deliver(self, operation)
  return true
end

---Start a new request, superseding this owner's previous request/callback.
---All completion callbacks are scheduled; no shell, synchronous wait, or download.
---@param connection EnhanceHelperConnection
---@param query string Unchanged server SQL
---@param callback EnhanceHelperCallback
---@param opts EnhanceHelperRunOptions?
function Runner:run(connection, query, callback, opts)
  assert(type(callback) == 'function', 'SQL Server helper callback is required')
  local previous = self.active
  self.active = nil -- Invalidate callbacks before terminating the predecessor.
  if previous then stop(previous) end
  local operation = { callback = callback, completed = false, queued = false, cancelled = false }
  self.active = operation
  local function fail(message)
    operation.completed = true
    operation.error = message
    deliver(self, operation)
  end

  local adapter = require('enhance.db.sqlserver_helper')
  local db = type(connection) == 'table' and connection.type or 'sqlserver'
  db = type(db) == 'string' and db:lower():gsub('[%s%-_]', '') or 'sqlserver'
  db = ({ mssql = 'sqlserver', mariadb = 'mysql', postgres = 'postgresql' })[db] or db
  local label = ({ sqlserver = 'SQL Server', mysql = 'MySQL', postgresql = 'PostgreSQL' })[db] or 'Database'
  operation.label = label
  local body, request_error = adapter.encode_request(connection, query, opts)
  if not body then fail(request_error); return end
  opts = opts or {}
  local timeout = opts.process_timeout_ms
  if timeout == nil then
    timeout = require('enhance.db.query_timeout').process_ms(opts)
  end
  if type(timeout) ~= 'number' or timeout ~= math.floor(timeout) or timeout < 1 or timeout > 90000000 then
    fail('Invalid ' .. label .. ' helper process timeout'); return
  end
  local resolved, path = pcall(self.deps.resolve, db)
  if not resolved or type(path) ~= 'string' or path == '' then
    fail(label .. ' helper unavailable; rebuild enhance.nvim in lazy.nvim'); return
  end
  local started, process = pcall(self.deps.spawn, { path }, {
    stdin = body, text = false, stderr = false, timeout = timeout,
  }, function(output)
    if self.active ~= operation or operation.completed or operation.cancelled then return end
    operation.completed = true
    if output.code == 124 then
      operation.error = label .. ' helper timed out'
    elseif output.signal ~= 0 and output.signal ~= nil then
      operation.error = label .. ' helper terminated unexpectedly'
    else
      operation.response, operation.error = adapter.decode_response(output.stdout, output.code, db)
    end
    deliver(self, operation)
  end)
  if not started or type(process) ~= 'table' or type(process.kill) ~= 'function' then
    fail('Failed to start ' .. label .. ' helper'); return
  end
  operation.process = process
end

---@param deps EnhanceHelperRunnerDependencies
---@return EnhanceHelperRunner
local function new(deps)
  return setmetatable({ deps = deps }, Runner)
end

---Create one owner per future query buffer/generation scope.
---Resolving a cached checksum is offline but synchronous; SQL execution is async.
---@return EnhanceHelperRunner
function M.new()
  return new({
    resolve = function(db) return require('enhance.helper_install').path(db) end,
    spawn = function(cmd, opts, callback) return vim.system(cmd, opts, callback) end,
    schedule = vim.schedule,
  })
end

M._new = new
return M
