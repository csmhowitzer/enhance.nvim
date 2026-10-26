-- Maintainer opt-in only; ordinary nvt runs neither use Docker nor credentials.
local selected = vim.env.ENHANCE_TEST_LINUX_RELEASE
if not selected then
  describe('Ubuntu 24.04 release candidates', function() pending('opt-in: set ENHANCE_TEST_LINUX_RELEASE=arm64|amd64|both') end)
  return
end
assert(selected == 'arm64' or selected == 'amd64' or selected == 'both', 'Invalid Linux release test architecture')

describe('Ubuntu 24.04 release candidates', function()
  local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
  local candidate = vim.env.ENHANCE_TEST_RELEASE_CANDIDATE or root .. '/dist/release-candidate-v1.1.1'
  local adapter = require('enhance.db.sqlserver_helper')
  local verified = {}
  local engines = {
    { name = 'Docker SQL Server', fixture = 'sqlserver', db = 'sqlserver' },
    { name = 'Docker MySQL', fixture = 'mysql', db = 'mysql' },
    { name = 'Docker PostgreSQL', fixture = 'postgres', db = 'postgresql' },
  }

  local function run(arch, family, body, version)
    local rid = arch == 'amd64' and 'linux-x64' or 'linux-arm64'
    local manifest = vim.json.decode(table.concat(vim.fn.readfile(candidate .. '/' .. family .. '/helper-release.json'), '\n'))
    assert.equals(1, manifest.schema)
    assert.equals('helper-v1.1.1', manifest.release)
    assert.equals(family == 'postgres' and 'postgres' or nil, manifest.helper)
    local artifact = assert(manifest.artifacts[rid], 'Candidate does not contain requested Linux architecture')
    assert.equals((family == 'postgres' and 'enhance-helper-postgres-' or 'enhance-helper-') .. rid, artifact.name)
    local path = candidate .. '/' .. family .. '/' .. artifact.name
    if not verified[path] then
      local hash = vim.fn.system({ 'shasum', '-a', '256', path })
      assert.equals(0, vim.v.shell_error, 'Candidate checksum tool failed')
      assert.equals(artifact.sha256, hash:match('^(%x+)'))
      verified[path] = true
    end
    local cmd = { 'docker', 'run', '--rm', '-i', '--platform', 'linux/' .. arch,
      '--mount', 'type=bind,source=' .. candidate .. ',target=/helpers,readonly',
      'enhance-release-check:ubuntu24-' .. arch, '/helpers/' .. family .. '/' .. artifact.name }
    if version then cmd[#cmd + 1] = '--version' end
    local output = vim.system(cmd, { stdin = body or '', text = false, timeout = 65000 }):wait()
    assert.is_true(output.code == 0 or output.code == 1, 'Container/helper failed or timed out; no private response printed')
    return output.stdout, output.code
  end

  local function execute(arch, engine, sql)
    local connections, err = require('enhance.config').load_connections('~/.local/share/enhance/connections.json')
    assert.is_nil(err)
    local connection
    for _, item in ipairs(connections) do
      if item.name == engine.name then connection = vim.deepcopy(item); break end
    end
    assert.is_not_nil(connection, 'Missing required local Docker connection')
    local server = connection.server or connection.host
    local host, suffix = server:match('^([^,:]+)(.*)$')
    assert.is_true(host == 'localhost' or host == '127.0.0.1', 'Only existing local Docker databases are allowed')
    connection.server = 'host.docker.internal' .. suffix
    local body = assert(adapter.encode_request(connection, sql))
    local stdout, code = run(arch, engine.db == 'postgresql' and 'postgres' or 'main', body)
    local response, decode_error = adapter.decode_response(stdout, code, engine.db)
    assert.is_nil(decode_error)
    return assert(response)
  end

  for _, arch in ipairs(selected == 'both' and { 'arm64', 'amd64' } or { selected }) do
    for _, family in ipairs({ 'main', 'postgres' }) do
      it('starts and rejects private malformed input on ' .. arch .. '/' .. family, function()
        local stdout, code = run(arch, family, '', true)
        assert.equals(0, code)
        local expected = { protocol = 1, helperVersion = '1.1.1' }
        if family == 'postgres' then expected.dbType = 'postgresql' end
        assert.are.same(expected, vim.json.decode(stdout))
        stdout, code = run(arch, family, '{private-test-marker')
        assert.equals(1, code)
        assert.is_nil(stdout:find('private-test-marker', 1, true))
        assert.equals('invalid_request', vim.json.decode(stdout).errors[1].kind)
      end)
    end
    for _, engine in ipairs(engines) do
      it('preserves live fields on ' .. arch .. '/' .. engine.db, function()
        local sql = table.concat(vim.fn.readfile(root .. '/tests/fixtures/c03-' .. engine.fixture .. '.sql'), '\n')
        local response = execute(arch, engine, sql)
        assert.is_true(response.ok, 'Live query failed; private diagnostics not printed')
        local sets = response.parsed_result.result_sets
        assert.equals(3, #sets)
        assert.are.same({ 'same', 'same', 'empty_value', 'literal_null', 'long_value', 'precise_value', 'binary_value' }, sets[1].headers)
        local precise = '123456789012345678901234567890.' .. (engine.db == 'sqlserver' and '12345678' or '123456789')
        local binary = engine.db == 'postgresql' and '\\x000aff' or '0x000AFF'
        assert.are.same({ { '  pipe|tab\tline\r\n雪  ', vim.NIL, '', 'NULL', string.rep('x', 10000), precise, binary } }, sets[1].rows)
        assert.are.same({ 'empty_header' }, sets[2].headers)
        assert.equals(0, #sets[2].rows)
        assert.are.same({ 'value' }, sets[3].headers)
        assert.are.same({ { 'second set' } }, sets[3].rows)
      end)
      it('retains earlier results and native later errors on ' .. arch .. '/' .. engine.db, function()
        local sql = "SELECT 'before error' AS value; SELECT CAST('c03-invalid-integer' AS "
          .. (engine.db == 'mysql' and 'UNSUPPORTED_C03_TYPE' or 'int') .. ') AS value;'
        local response = execute(arch, engine, sql)
        assert.is_false(response.ok)
        assert.is_true(#response.errors > 0)
        assert.are.same({ { 'before error' } }, response.parsed_result.rows)
        if engine.db ~= 'sqlserver' then
          assert.is_string(response.errors[1].sqlState)
          assert.equals(5, #response.errors[1].sqlState)
        end
      end)
    end
  end
end)
