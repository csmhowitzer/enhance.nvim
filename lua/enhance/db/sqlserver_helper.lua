-- Pure protocol boundary used by the structured SQL Server query runner.
local M = {}

---@class EnhanceHelperConnection
---@field server string? Preferred server address
---@field host string? Server alias
---@field database string
---@field user string? SQL authentication user; omitted for integrated authentication
---@field username string? User alias
---@field password string?
---@field port integer? Separate TCP port (1–65535)
---@field type string? Database type; defaults to SQL Server
---@field ssl_mode string? MySQL/PostgreSQL TLS mode; default prefer (CLI-compatible)
---@field trust_server_certificate boolean? Explicit opt-out of certificate validation

---@class EnhanceHelperTimeouts
---@field connect_timeout_seconds integer? Default 15; range 1–300
---@field command_timeout_seconds integer? Default 30; range 1–86400

---@class EnhanceHelperDiagnostic
---@field message string
---@field kind string? Required on errors only
---@field number integer|userdata? Nullable on errors
---@field severity integer|userdata?
---@field state integer|userdata?
---@field line integer|userdata?

---@class EnhanceHelperResultSet
---@field headers string[] Exact positional names, including unnamed/duplicate columns
---@field column_types string[] Driver type names
---@field rows (string|userdata)[][] SQL NULL remains vim.NIL, never a missing element
---@field metadata table

---@class EnhanceHelperParsedResult
---@field headers string[]? Present for zero/one result set
---@field rows (string|userdata)[][]? Present for zero/one result set
---@field column_types string[]? Present for one result set
---@field multiple_results boolean? Present for multiple result sets
---@field result_sets EnhanceHelperResultSet[]? Present for multiple result sets
---@field metadata table

---@class EnhanceHelperDecodedResponse
---@field ok boolean Query status, independent of whether earlier rows exist
---@field parsed_result EnhanceHelperParsedResult
---@field messages EnhanceHelperDiagnostic[]
---@field errors EnhanceHelperDiagnostic[]
---@field affected_rows integer|userdata Aggregate driver count or vim.NIL; not per-result count
---@field duration_ms number

local function integer(value, minimum, maximum)
  return type(value) == 'number' and value == math.floor(value)
    and value >= minimum and value <= maximum
end

local function nonblank(value)
  return type(value) == 'string' and value:find('%S') ~= nil
end

local function object(value)
  return type(value) == 'table' and not vim.islist(value)
end

local function array(value)
  return type(value) == 'table' and vim.islist(value)
end

---Build only a stdin body; never resolves a helper or starts a process.
---TLS validation defaults on, unlike the legacy CLI adapter's implicit -C.
---@param connection EnhanceHelperConnection
---@param query string Server SQL, copied without trimming or rewriting
---@param opts EnhanceHelperTimeouts?
---@return string? body
---@return string? error Generic validation error, never input contents
function M.encode_request(connection, query, opts)
  local invalid = 'Invalid SQL Server helper request'
  if type(connection) ~= 'table' or not nonblank(query) then return nil, invalid end
  if opts ~= nil and type(opts) ~= 'table' then return nil, invalid end
  opts = opts or {}
  local db = connection.type or 'sqlserver'
  if type(db) ~= 'string' then return nil, invalid end
  db = db:lower():gsub('[%s%-_]', '')
  db = ({ mssql = 'sqlserver', mariadb = 'mysql', postgres = 'postgresql' })[db] or db
  if db ~= 'sqlserver' and db ~= 'mysql' and db ~= 'postgresql' then return nil, invalid end
  local server = connection.server
  if server == nil then server = connection.host end
  if server == nil and db ~= 'sqlserver' then server = 'localhost' end
  local user = connection.user
  if user == nil then user = connection.username end
  local connect_timeout = opts.connect_timeout_seconds
  if connect_timeout == nil then connect_timeout = 15 end
  local command_timeout = opts.command_timeout_seconds
  if command_timeout == nil then command_timeout = 30 end
  if not nonblank(server) or not nonblank(connection.database)
    or (user ~= nil and not nonblank(user))
    or (connection.password ~= nil and (type(connection.password) ~= 'string' or user == nil))
    or (connection.trust_server_certificate ~= nil and type(connection.trust_server_certificate) ~= 'boolean')
    or not integer(connect_timeout, 1, 300) or not integer(command_timeout, 1, 86400) then
    return nil, invalid
  end
  if connection.port ~= nil and not integer(connection.port, 1, 65535) then return nil, invalid end
  if connection.port ~= nil and db == 'sqlserver' then
    if not integer(connection.port, 1, 65535) then return nil, invalid end
    -- Refuse competing endpoint declarations rather than silently picking one.
    if server:find(',', 1, true) or server:find('\\', 1, true) then return nil, invalid end
    server = server .. ',' .. tostring(connection.port)
  end
  if db ~= 'sqlserver' then
    local modes = { disable = true, prefer = true, require = true, ['verify-ca'] = true, ['verify-full'] = true }
    if connection.trust_server_certificate == true or (connection.ssl_mode ~= nil and not modes[connection.ssl_mode])
      or (db == 'postgresql' and (not nonblank(user) or query:find('\0', 1, true))) then return nil, invalid end
  end
  local request = {
    protocol = 1, query = query, commandTimeoutSeconds = command_timeout,
    connection = {
      server = server, database = connection.database, user = user, password = connection.password,
      trustServerCertificate = connection.trust_server_certificate == true,
      connectTimeoutSeconds = connect_timeout,
    },
  }
  if db ~= 'sqlserver' then
    request.dbType = db
    request.connection.port = connection.port
    request.connection.sslMode = connection.ssl_mode or 'prefer'
  end
  local ok, body = pcall(vim.json.encode, request)
  if not ok then return nil, invalid end
  return body
end

local function diagnostics(values, errors)
  if not array(values) then return false end
  for _, value in ipairs(values) do
    if not object(value) or type(value.message) ~= 'string'
      or (errors and not nonblank(value.kind)) then return false end
    if value.sqlState ~= nil and value.sqlState ~= vim.NIL
      and (type(value.sqlState) ~= 'string' or not value.sqlState:match('^[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]$')) then return false end
    for _, key in ipairs({ 'number', 'severity', 'state', 'line' }) do
      local field = value[key]
      if not (errors and (field == nil or field == vim.NIL))
        and not integer(field, -2147483648, 2147483647) then return false end
    end
  end
  return true
end

local function result_sets(values, db)
  if not array(values) then return nil end
  local sets = {}
  for _, value in ipairs(values) do
    if not object(value) or not array(value.columns) or not array(value.rows) then return nil end
    local headers, types, formats, has_formats = {}, {}, {}, false
    for i, column in ipairs(value.columns) do
      if not object(column) or type(column.name) ~= 'string' or not nonblank(column.type) then return nil end
      headers[i], types[i] = column.name, column.type
      if column.format ~= nil and column.format ~= 0 and column.format ~= 1 then return nil end
      formats[i] = column.format or 0
      has_formats = has_formats or column.format ~= nil
    end
    for _, row in ipairs(value.rows) do
      if not array(row) or #row ~= #headers then return nil end
      for _, cell in ipairs(row) do
        if cell ~= vim.NIL and type(cell) ~= 'string' then return nil end
      end
    end
    sets[#sets + 1] = {
      headers = headers, column_types = types, column_formats = has_formats and formats or nil, rows = value.rows,
      metadata = { db_type = db, transport = 'helper', protocol = 1 },
    }
  end
  return sets
end

---Validate the whole envelope before exposing any results. No text fallback.
---A valid error envelope is returned with ok=false, not disguised as a decode error.
---@param stdout string Complete, unmodified stdout JSON
---@param exit_code integer Helper process exit code (0 success, 1 structured failure)
---@return EnhanceHelperDecodedResponse? response
---@return string? error Generic protocol error, never payload contents
function M.decode_response(stdout, exit_code, db)
  db = db or 'sqlserver'
  if db ~= 'sqlserver' and db ~= 'mysql' and db ~= 'postgresql' then return nil, 'Invalid helper database type' end
  local invalid = 'Invalid SQL Server helper response'
  if type(stdout) ~= 'string' or (exit_code ~= 0 and exit_code ~= 1) then return nil, invalid end
  local ok, value = pcall(vim.json.decode, stdout, { luanil = { object = false, array = false } })
  if not ok or not object(value) or value.protocol ~= 1 or type(value.ok) ~= 'boolean'
    or exit_code ~= (value.ok and 0 or 1)
    or not diagnostics(value.messages, false) or not diagnostics(value.errors, true)
    or (value.ok and #value.errors ~= 0) or (not value.ok and #value.errors == 0)
    or (value.affectedRows ~= vim.NIL and not integer(value.affectedRows, 0, 2147483647))
    or type(value.durationMs) ~= 'number' or value.durationMs < 0 or value.durationMs >= math.huge
    or value.durationMs ~= value.durationMs then return nil, invalid end
  local sets = result_sets(value.resultSets, db)
  if not sets then return nil, invalid end
  local parsed
  if #sets == 1 then
    parsed = sets[1]
  else
    local metadata = { db_type = db, transport = 'helper', protocol = 1 }
    parsed = #sets == 0 and { headers = {}, rows = {}, metadata = metadata }
      or { multiple_results = true, result_sets = sets, metadata = metadata }
  end
  return {
    ok = value.ok, parsed_result = parsed, messages = value.messages, errors = value.errors,
    affected_rows = value.affectedRows, duration_ms = value.durationMs,
  }
end

return M
