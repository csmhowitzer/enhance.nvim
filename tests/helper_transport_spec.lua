describe('structured SQL Server adapter boundary', function()
  local function adapter() return require('enhance.db.sqlserver_helper') end
  local function response()
    return { protocol = 1, ok = true, resultSets = {}, messages = {}, errors = {},
      affectedRows = vim.NIL, durationMs = 1.5 }
  end
  local function decode(value, code)
    return adapter().decode_response(vim.json.encode(value), code or 0)
  end

  it('preserves positional NULLs, empty text, and arbitrary text without CLI parsing', function()
    local value = response()
    local text = '  a|b\r\nc\t\\\0雪  ' .. string.rep('x', 10000)
    value.resultSets = { { columns = { { name = '', type = 'nvarchar' },
      { name = 'same', type = 'varchar' }, { name = 'same', type = 'varchar' } },
      rows = { { vim.NIL, '', text }, { 'NULL', vim.NIL, vim.NIL } } } }
    local result, err = decode(value)
    assert.is_nil(err)
    assert.are.same({ '', 'same', 'same' }, result.parsed_result.headers)
    assert.are.same({ 'nvarchar', 'varchar', 'varchar' }, result.parsed_result.column_types)
    assert.are.same(value.resultSets[1].rows, result.parsed_result.rows)
    assert.equals(3, #result.parsed_result.rows[2])
    assert.equals(vim.NIL, result.affected_rows)
    assert.equals('sqlserver', result.parsed_result.metadata.db_type)
  end)

  it('retains multiple and empty sets without attaching aggregate DML counts to SELECTs', function()
    local value = response()
    value.affectedRows = 7
    value.resultSets = { { columns = { { name = 'id', type = 'int' } }, rows = { { '1' } } },
      { columns = { { name = 'empty', type = 'nvarchar' } }, rows = {} } }
    local result = decode(value)
    assert.is_true(result.parsed_result.multiple_results)
    assert.equals(2, #result.parsed_result.result_sets)
    assert.are.same({ 'empty' }, result.parsed_result.result_sets[2].headers)
    assert.are.same({}, result.parsed_result.result_sets[2].rows)
    assert.is_nil(result.parsed_result.result_sets[1].metadata.row_count)
    assert.equals(7, result.affected_rows)
  end)

  it('retains messages and structured errors without treating partial rows as success', function()
    local value = response()
    value.ok = false
    value.messages = { { message = 'hello|world\nnext', number = 0, severity = 0, state = 1, line = 2 } }
    value.errors = { { kind = 'sql_error', message = 'constraint', number = 2627,
      severity = 14, state = 1, line = 3 } }
    value.resultSets = { { columns = { { name = 'id', type = 'int' } }, rows = { { '1' } } } }
    local result, err = decode(value, 1)
    assert.is_nil(err)
    assert.is_false(result.ok)
    assert.are.same(value.messages, result.messages)
    assert.are.same(value.errors, result.errors)
    assert.equals('1', result.parsed_result.rows[1][1])
  end)

  it('represents DML-only success without inventing result rows', function()
    local value = response()
    value.affectedRows = 0
    local result = decode(value)
    assert.are.same({}, result.parsed_result.headers)
    assert.are.same({}, result.parsed_result.rows)
    assert.equals(0, result.affected_rows)
    assert.equals(1.5, result.duration_ms)
  end)

  local invalid = {
    { 'unsupported version', function(v) v.protocol = 2 end },
    { 'missing success', function(v) v.ok = nil end },
    { 'object instead of result array', function(v) v.resultSets = vim.empty_dict() end },
    { 'NULL instead of messages', function(v) v.messages = vim.NIL end },
    { 'negative duration', function(v) v.durationMs = -1 end },
    { 'missing aggregate count', function(v) v.affectedRows = nil end },
    { 'fractional aggregate count', function(v) v.affectedRows = 1.5 end },
    { 'success with errors', function(v) v.errors = { { kind = 'sql_error', message = 'secret-value' } } end },
    { 'failure without errors', function(v) v.ok = false end },
    { 'row width mismatch', function(v) v.resultSets = { { columns = { { name = 'x', type = 'int' } }, rows = { {} } } } end },
    { 'number instead of scalar string', function(v) v.resultSets = { { columns = { { name = 'x', type = 'int' } }, rows = { { 123 } } } } end },
    { 'missing column type', function(v) v.resultSets = { { columns = { { name = 'x' } }, rows = {} } } end },
    { 'object instead of rows', function(v) v.resultSets = { { columns = {}, rows = vim.empty_dict() } } end },
    { 'invalid message metadata', function(v) v.messages = { { message = 'secret-value' } } end },
    { 'invalid error metadata', function(v) v.ok = false; v.errors = { { kind = 'sql_error', message = 'secret-value', number = 'bad' } } end },
  }
  for _, case in ipairs(invalid) do
    it('rejects ' .. case[1] .. ' without exposing payloads or guessing cells', function()
      local value = response()
      case[2](value)
      local result, err = decode(value, value.ok == false and 1 or 0)
      assert.is_nil(result)
      assert.equals('Invalid SQL Server helper response', err)
    end)
  end

  it('rejects text, malformed JSON, trailing output, and non-object JSON', function()
    for _, text in ipairs({ 'secret-value|raw-output', '{secret-value', 'null', '[]',
      vim.json.encode(response()) .. '\nsecret-value', '42' }) do
      local result, err = adapter().decode_response(text, 0)
      assert.is_nil(result)
      assert.equals('Invalid SQL Server helper response', err)
    end
  end)

  it('rejects startup/signal failures and exit/response disagreement', function()
    for _, code in ipairs({ -1, 1, 2, 137 }) do
      local result, err = decode(response(), code)
      assert.is_nil(result)
      assert.equals('Invalid SQL Server helper response', err)
    end
    local value = response()
    value.ok = false
    value.errors = { { kind = 'cancelled', message = 'cancelled' } }
    assert.is_nil(decode(value, 0))
  end)

  it('builds stdin JSON with unchanged SQL and connection aliases, not process arguments', function()
    local sql = "  SELECT 'a--b', 'a|b';\n-- retain\n"
    local body, err = adapter().encode_request({ host = 'host', database = 'db;other',
      username = 'user', password = 'p;word', port = 1444 }, sql)
    assert.is_nil(err)
    local value = vim.json.decode(body)
    assert.equals(sql, value.query)
    assert.equals(1, value.protocol)
    assert.equals('host,1444', value.connection.server)
    assert.equals('db;other', value.connection.database)
    assert.equals('user', value.connection.user)
    assert.equals('p;word', value.connection.password)
    assert.is_false(value.connection.trustServerCertificate)
    assert.equals(15, value.connection.connectTimeoutSeconds)
    assert.equals(240, value.commandTimeoutSeconds)
  end)

  it('keeps integrated authentication and explicit TLS/timeout choices', function()
    local body = adapter().encode_request({ server = 'server', database = 'db', trust_server_certificate = true },
      'SELECT 1', { connect_timeout_seconds = 25, command_timeout_seconds = 60 })
    local value = vim.json.decode(body)
    assert.is_nil(value.connection.user)
    assert.is_nil(value.connection.password)
    assert.is_true(value.connection.trustServerCertificate)
    assert.equals(25, value.connection.connectTimeoutSeconds)
    assert.equals(60, value.commandTimeoutSeconds)
  end)

  it('rejects invalid requests without exposing credentials', function()
    local cases = {
      { {}, 'SELECT 1' }, { { server = 's', database = 'd', password = 'secret-value' }, 'SELECT 1' },
      { { server = 's', database = 'd', user = '' }, 'SELECT 1' },
      { { server = 's', database = 'd', port = '1444' }, 'SELECT 1' },
      { { server = 's', database = 'd', port = 0 }, 'SELECT 1' },
      { { server = 's', database = 'd', trust_server_certificate = 'yes' }, 'SELECT 1' },
      { { server = 's', database = 'd' }, '  ' },
      { { server = 's', database = 'd' }, 'SELECT 1', { command_timeout_seconds = 0 } },
    }
    for _, case in ipairs(cases) do
      local body, err = adapter().encode_request(unpack(case))
      assert.is_nil(body)
      assert.equals('Invalid SQL Server helper request', err)
    end
  end)

  it('rejects explicit false fields instead of treating them as absent defaults or aliases', function()
    for _, case in ipairs({
      { { server = false, host = 's', database = 'd' }, 'SELECT 1' },
      { { server = 's', database = 'd', user = false, username = 'u' }, 'SELECT 1' },
      { { server = 's', database = 'd' }, 'SELECT 1', { command_timeout_seconds = false } },
      { { server = 's', database = 'd' }, 'SELECT 1', { connect_timeout_seconds = false } },
    }) do
      local body, err = adapter().encode_request(unpack(case))
      assert.is_nil(body)
      assert.equals('Invalid SQL Server helper request', err)
    end
  end)

  it('rejects a separate port when the endpoint already specifies a port or instance', function()
    for _, server in ipairs({ 'server,1433', 'server\\instance' }) do
      local body, err = adapter().encode_request({ server = server, database = 'd', port = 1444 }, 'SELECT 1')
      assert.is_nil(body)
      assert.equals('Invalid SQL Server helper request', err)
    end
  end)

  local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
  local executable = root .. '/dist/helper-publish/osx-arm64/enhance-helper'
  if vim.fn.executable(executable) == 1 then
    it('decodes a real self-contained helper failure without a database connection', function()
      local output = vim.fn.system({ executable }, '{secret-value')
      local result, err = adapter().decode_response(output, vim.v.shell_error)
      assert.is_nil(err)
      assert.is_false(result.ok)
      assert.equals('invalid_request', result.errors[1].kind)
      assert.are.same({}, result.parsed_result.rows)
      assert.is_nil(result.errors[1].message:find('secret-value', 1, true))
    end)
  end

  it('does not invoke processes, lookup/install helpers, or legacy text parsing', function()
    local originals = { system = vim.fn.system, jobstart = vim.fn.jobstart, parser = package.loaded['enhance.parser'],
      installer = package.loaded['enhance.helper_install'] }
    local function forbidden() error('boundary must not execute or parse CLI text') end
    vim.fn.system, vim.fn.jobstart = forbidden, forbidden
    package.loaded['enhance.parser'] = { parse = forbidden }
    package.loaded['enhance.helper_install'] = { install = forbidden, path = forbidden }
    local ok, err = pcall(function()
      assert.is_string(adapter().encode_request({ server = 's', database = 'd' }, 'SELECT 1'))
      assert.is_true(decode(response()).ok)
    end)
    vim.fn.system, vim.fn.jobstart = originals.system, originals.jobstart
    package.loaded['enhance.parser'], package.loaded['enhance.helper_install'] = originals.parser, originals.installer
    assert.is_true(ok, tostring(err))
  end)
end)
