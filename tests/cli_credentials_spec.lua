describe('CLI credential isolation', function()
  it('bounds synchronous catalog/probe commands and reports missing executables', function()
    local cli = require('enhance.db.cli_credentials')
    local old_system = vim.system
    vim.system = function(_, opts)
      assert.equals(30000, opts.timeout)
      return { wait = function() return { stdout = '', stderr = '', code = 124 } end }
    end
    local ok, err = pcall(function()
      local output, code = cli.system({ 'psql' }, {}, 'postgresql')
      assert.equals(124, code)
      assert.matches('timed out', output)
      vim.system = function() error('executable not found') end
      output, code = cli.system({ 'missing' }, {}, 'postgresql')
      assert.equals(-1, code)
      assert.matches('Failed to start', output)
    end)
    vim.system = old_system
    if not ok then error(err) end
  end)

  it('returns probe results asynchronously without waiting on a CLI', function()
    local cli = require('enhance.db.cli_credentials')
    local old_system = vim.system
    local finish, output, exit_code
    vim.system = function(_, opts, callback)
      assert.equals(30000, opts.timeout)
      assert.equals('private', opts.env.PGPASSWORD)
      finish = callback
      return { kill = function() end }
    end
    local ok, err = pcall(function()
      cli.system_async({ 'psql' }, { password = 'private' }, 'postgresql', function(text, code)
        output, exit_code = text, code
      end)
      assert.is_nil(output)
      finish({ stdout = '1', code = 0 })
      assert.is_true(vim.wait(200, function() return output ~= nil end, 10))
      assert.equals('1', output)
      assert.equals(0, exit_code)
    end)
    vim.system = old_system
    if not ok then error(err) end
  end)
  it('keeps SQL Server and MySQL passwords out of command arguments', function()
    local sql = require('enhance.db.sqlserver').build_cmd({
      server = 'localhost', database = 'db', user = 'sa', password = 'sql-private',
    }, { query = 'SELECT 1;' })
    local mysql = require('enhance.db.mysql').build_cmd({
      host = 'localhost', database = 'db', user = 'root', password = 'mysql-private',
    }, { query = 'SELECT 1;' })
    for _, cmd in ipairs({ sql, mysql }) do
      for _, arg in ipairs(cmd) do
        assert.is_nil(arg:find('private', 1, true))
      end
    end
  end)

  it('passes independent credentials to children without changing the parent', function()
    local cli = require('enhance.db.cli_credentials')
    local old_system = vim.system
    local parent = vim.env.PGPASSWORD
    local launches = {}
    vim.system = function(cmd, opts)
      launches[#launches + 1] = { cmd = cmd, env = opts.env }
      return { wait = function() return { stdout = 'ok', stderr = '', code = 0 } end }
    end
    local ok, err = pcall(function()
      cli.system({ 'psql', '-c', 'SELECT 1' }, { password = 'one' }, 'postgresql')
      cli.system({ 'psql', '-c', 'SELECT 1' }, { password = 'two' }, 'postgresql')
      assert.equals('one', launches[1].env.PGPASSWORD)
      assert.equals('two', launches[2].env.PGPASSWORD)
      assert.equals(parent, vim.env.PGPASSWORD)
      assert.equals('sql-private', cli.env({ password = 'sql-private' }, 'sqlserver').SQLCMDPASSWORD)
      assert.equals('mysql-private', cli.env({ password = 'mysql-private' }, 'mysql').MYSQL_PWD)
    end)
    vim.system = old_system
    if not ok then error(err) end
  end)

  it('does not clear an existing PGPASSWORD after a PostgreSQL probe', function()
    local adapter = require('enhance.db.postgres')
    local old_system, old_parent = vim.system, vim.env.PGPASSWORD
    vim.env.PGPASSWORD = 'original'
    vim.system = function(_, opts)
      assert.equals('probe-only', opts.env.PGPASSWORD)
      assert.equals('original', vim.env.PGPASSWORD)
      return { wait = function() return { stdout = '1', stderr = '', code = 0 } end }
    end
    local ok, err = pcall(function()
      assert.is_true(adapter.test_connection({ host = 'localhost', database = 'db', password = 'probe-only' }))
      assert.equals('original', vim.env.PGPASSWORD)
    end)
    vim.system, vim.env.PGPASSWORD = old_system, old_parent
    if not ok then error(err) end
  end)

  it('passes the configured password to a real child without replacing the parent value', function()
    local cli = require('enhance.db.cli_credentials')
    local parent = vim.env.PGPASSWORD
    vim.env.PGPASSWORD = 'existing-parent'
    local ok, err = pcall(function()
      local _, code = cli.system({ 'sh', '-c', 'test "$PGPASSWORD" = child-only' },
        { password = 'child-only' }, 'postgresql')
      assert.equals(0, code)
      assert.equals('existing-parent', vim.env.PGPASSWORD)
      local _, masked = cli.system({ 'sh', '-c', 'test -z "$PGPASSWORD"' }, {}, 'postgresql')
      assert.equals(0, masked)
    end)
    vim.env.PGPASSWORD = parent
    if not ok then error(err) end
  end)
end)
