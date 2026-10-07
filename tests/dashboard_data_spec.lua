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
end)
