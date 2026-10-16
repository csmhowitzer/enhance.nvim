describe('enhance dashboard SQL Server estimates', function()
  local data = require('enhance.dashboard_data')
  local original_jobstart

  before_each(function()
    original_jobstart = vim.fn.jobstart
  end)

  after_each(function()
    vim.fn.jobstart = original_jobstart
  end)

  it('parses catalog rows without treating sqlcmd footers as data', function()
    assert.same({
      { name = 'dbo.Artists', count = 1234 },
      { name = 'archive.Albums', count = 0 },
    }, data.parse_sqlserver_rows({ 'dbo.Artists|1234', 'archive.Albums | 0', '(2 rows affected)' }))
  end)

  it('fetches only top-eight metadata asynchronously and returns parsed counts', function()
    local received
    vim.fn.jobstart = function(cmd, opts)
      local query = cmd[#cmd]
      assert.is_not_nil(query:find('TOP (8)', 1, true))
      assert.is_not_nil(query:find('sys.partitions', 1, true))
      opts.on_stdout(nil, { 'dbo.Artists|1200', 'dbo.Albums|350', '(2 rows affected)' })
      opts.on_exit(nil, 0)
      return 1
    end
    data.fetch_sqlserver_rows({ type = 'sqlserver', server = 'local', database = 'demo' },
      function(rows) received = rows end)
    assert.is_true(vim.wait(200, function() return received ~= nil end, 10))
    assert.same({ { name = 'dbo.Artists', count = 1200 }, { name = 'dbo.Albums', count = 350 } }, received)
  end)

  it('isolates concurrent dashboard credentials from argv and the parent', function()
    local parent = vim.env.SQLCMDPASSWORD
    local launches = {}
    vim.fn.jobstart = function(cmd, opts)
      launches[#launches + 1] = { cmd = cmd, env = opts.env }
      return #launches
    end
    for _, password in ipairs({ 'first-private', 'second-private' }) do
      data.fetch_sqlserver_rows({ server = 'local', database = 'demo', user = 'sa', password = password }, function() end)
    end
    assert.equals('first-private', launches[1].env.SQLCMDPASSWORD)
    assert.equals('second-private', launches[2].env.SQLCMDPASSWORD)
    for _, launch in ipairs(launches) do
      for _, arg in ipairs(launch.cmd) do assert.is_nil(arg:find('private', 1, true)) end
    end
    assert.equals(parent, vim.env.SQLCMDPASSWORD)
  end)

  it('keeps the dashboard usable when metadata cannot be retrieved', function()
    local called = false
    vim.fn.jobstart = function(_, opts)
      opts.on_stderr(nil, { 'Catalog unavailable' })
      opts.on_exit(nil, 1)
      return 1
    end
    data.fetch_sqlserver_rows({ type = 'sqlserver', server = 'local', database = 'demo' },
      function(rows)
        assert.is_nil(rows)
        called = true
      end)
    assert.is_true(vim.wait(200, function() return called end, 10))
  end)

  it('stops hung metadata jobs and returns unavailable once', function()
    local old_defer, old_stop = vim.defer_fn, vim.fn.jobstop
    local fire, opts, stopped, calls = nil, nil, nil, 0
    vim.defer_fn = function(fn, ms)
      assert.equals(30000, ms)
      fire = fn
      return { is_closing = function() return false end, stop = function() end, close = function() end }
    end
    vim.fn.jobstart = function(_, options) opts = options; return 56 end
    vim.fn.jobstop = function(job) stopped = job; return 1 end
    local ok, err = pcall(function()
      data.fetch_sqlserver_rows({ type = 'sqlserver', server = 'local', database = 'demo' }, function(rows)
        assert.is_nil(rows)
        calls = calls + 1
      end)
      fire()
      opts.on_exit(nil, 0)
      assert.equals(56, stopped)
      assert.is_true(vim.wait(200, function() return calls == 1 end, 10))
    end)
    vim.defer_fn, vim.fn.jobstop = old_defer, old_stop
    if not ok then error(err) end
  end)

  it('fetches used space from all database data files without counting log files', function()
    assert.equals(1536, data.parse_database_size({ '1536', '(1 row affected)' }))
    assert.is_nil(data.parse_database_size({ 'NULL', '(1 row affected)' }))
    local received
    vim.fn.jobstart = function(cmd, opts)
      local query = cmd[#cmd]
      assert.is_not_nil(query:find("FILEPROPERTY(name, 'SpaceUsed')", 1, true))
      assert.is_not_nil(query:find('sys.database_files', 1, true))
      assert.is_not_nil(query:find('WHERE type = 0', 1, true))
      assert.is_not_nil(query:find(' * 8 AS data_kb', 1, true))
      opts.on_stdout(nil, { '2048', '(1 row affected)' })
      opts.on_exit(nil, 0)
      return 1
    end
    data.fetch_database_size({ type = 'sqlserver', server = 'local', database = 'demo' },
      function(size) received = size end)
    assert.is_true(vim.wait(200, function() return received ~= nil end, 10))
    assert.equals(2048, received)
  end)

  it('fetches pinned tables outside the top eight, handling bare and qualified names', function()
    local received
    vim.fn.jobstart = function(cmd, opts)
      local query = cmd[#cmd]
      assert.is_not_nil(query:find("t.name IN (N'Artists')", 1, true))
      assert.is_not_nil(query:find("SCHEMA_NAME(t.schema_id) = N'dbo' AND t.name = N'O''Brien'", 1, true))
      assert.is_nil(query:find('TOP (8)', 1, true))
      opts.on_stdout(nil, { 'dbo.Artists|210', "dbo.O'Brien|75" })
      opts.on_exit(nil, 0)
      return 1
    end
    data.fetch_pinned_rows({ type = 'sqlserver', server = 'local', database = 'demo' },
      { 'Artists', "dbo.O'Brien" }, function(rows) received = rows end)
    assert.is_true(vim.wait(200, function() return received ~= nil end, 10))
    assert.same({ { name = 'dbo.Artists', count = 210 }, { name = "dbo.O'Brien", count = 75 } }, received)
  end)

  it('matches pinned quoted schema and table components without confusing dots or apostrophes', function()
    local received
    vim.fn.jobstart = function(cmd, opts)
      local query = cmd[#cmd]
      assert.is_not_nil(query:find("SCHEMA_NAME(t.schema_id) = N'a.b' AND t.name = N'O''Brien'", 1, true))
      assert.is_not_nil(query:find("SCHEMA_NAME(t.schema_id) = N'a' AND t.name = N'b.O''Brien'", 1, true))
      opts.on_stdout(nil, {})
      opts.on_exit(nil, 0)
      return 1
    end
    data.fetch_pinned_rows({ type = 'sqlserver', server = 'local', database = 'demo' },
      { "[a.b].[O'Brien]", "[a].[b.O'Brien]" }, function(rows) received = rows end)
    assert.is_true(vim.wait(200, function() return received ~= nil end, 10))
  end)

  it('fetches columns, real indexes, and allocated data size for pinned tables in one query', function()
    local received
    vim.fn.jobstart = function(cmd, opts)
      local query = cmd[#cmd]
      assert.is_not_nil(query:find('sys.columns', 1, true))
      assert.is_not_nil(query:find('sys.indexes', 1, true))
      assert.is_not_nil(query:find('i.index_id > 0', 1, true))
      assert.is_not_nil(query:find('sys.allocation_units', 1, true))
      assert.is_not_nil(query:find('p.index_id IN (0, 1)', 1, true))
      assert.is_not_nil(query:find("t.name IN (N'Artists')", 1, true))
      assert.is_not_nil(query:find("SCHEMA_NAME(t.schema_id) = N'dbo' AND t.name = N'O''Brien'", 1, true))
      opts.on_stdout(nil, { 'dbo.Artists|12|3|2048', "dbo.O'Brien|0|0|0", '(2 rows affected)' })
      opts.on_exit(nil, 0)
      return 1
    end
    data.fetch_pinned_details({ type = 'sqlserver', server = 'local', database = 'demo' },
      { 'Artists', "dbo.O'Brien" }, function(details) received = details end)
    assert.is_true(vim.wait(200, function() return received ~= nil end, 10))
    assert.same({
      { name = 'dbo.Artists', columns = 12, indexes = 3, data_kb = 2048 },
      { name = "dbo.O'Brien", columns = 0, indexes = 0, data_kb = 0 },
    }, received)
  end)
end)
