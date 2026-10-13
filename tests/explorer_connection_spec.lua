describe('explorer CLI connection parity', function()
  local explorer, cli, original_system, calls

  before_each(function()
    package.loaded['enhance.explorer'] = nil
    explorer = require('enhance.explorer')
    cli = require('enhance.db.cli_credentials')
    original_system = cli.system
    calls = {}
    cli.system = function(cmd, connection, db_type)
      calls[#calls + 1] = { cmd = cmd, connection = connection, db_type = db_type,
        env = cli.env(connection, db_type) }
      return 'Artists\n', 0
    end
  end)

  after_each(function()
    cli.system = original_system
  end)

  local function flag(cmd, name)
    for i, arg in ipairs(cmd) do
      if arg == name then return cmd[i + 1] end
    end
  end

  for _, case in ipairs({
    { type = 'mariadb', adapter = 'mysql', port_flag = '-P', port = 3307,
      user_flag = '-u', env_key = 'MYSQL_PWD', row_flag = '-N',
      discovery_flag = '-s', script_flag = '-B' },
    { type = 'postgres', adapter = 'postgres', port_flag = '-p', port = 5544,
      user_flag = '-U', env_key = 'PGPASSWORD', row_flag = '-t',
      discovery_flag = '-A', script_flag = '-A' },
  }) do
    it('uses ' .. case.type .. ' connection settings for discovery and script queries', function()
      local connection = { name = 'C05-' .. case.type, type = case.type,
        host = 'remote.example', port = case.port, database = 'sample',
        username = 'alias_user', password = 'private-child' }
      assert.same({ case.adapter == 'mysql' and '`Artists`' or 'Artists' },
        explorer._fetch_tables(connection, true))
      assert.equals('Artists\n', explorer._execute_query_for_script(connection, 'SELECT 1;'))
      assert.equals(2, #calls)
      local adapter = require('enhance.db.' .. case.adapter)
      local baseline = adapter.build_cmd(connection, { query = 'SELECT 1;' })
      for index, call in ipairs(calls) do
        assert.equals(connection, call.connection)
        assert.equals(connection.host, flag(call.cmd, '-h'))
        assert.equals(tostring(case.port), flag(call.cmd, case.port_flag) or '')
        assert.equals('alias_user', flag(call.cmd, case.user_flag) or '')
        assert.equals(flag(baseline, case.port_flag), flag(call.cmd, case.port_flag) or '')
        assert.equals(flag(baseline, case.user_flag), flag(call.cmd, case.user_flag) or '')
        assert.equals('private-child', call.env[case.env_key])
        assert.is_true(vim.tbl_contains(call.cmd, case.row_flag))
        assert.is_true(vim.tbl_contains(call.cmd,
          index == 1 and case.discovery_flag or case.script_flag))
        for _, arg in ipairs(call.cmd) do assert.is_nil(arg:find('private-child', 1, true)) end
      end
    end)
  end

  it('does not inherit a PostgreSQL password when none is configured', function()
    local connection = { name = 'C05-no-password', type = 'postgresql',
      database = 'sample', username = 'alias_user' }
    explorer._fetch_tables(connection, true)
    assert.equals('', calls[1].env.PGPASSWORD)
    assert.is_true(vim.tbl_contains(calls[1].cmd, '-w'))
  end)
end)
