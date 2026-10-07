describe('enhance SQL Server table dashboard catalog', function()
  local data = require('enhance.table_dashboard_data')
  local original_jobstart, original_readfile
  local conn = { type = 'sqlserver', server = 'local', database = 'demo' }

  before_each(function()
    original_jobstart, original_readfile = vim.fn.jobstart, vim.fn.readfile
  end)

  after_each(function()
    vim.fn.jobstart, vim.fn.readfile = original_jobstart, original_readfile
  end)

  it('generates a CREATE TABLE script with identity, defaults, and ordered primary key', function()
    local received
    vim.fn.jobstart = function(cmd, opts)
      local sql = cmd[#cmd]
      assert.is_not_nil(sql:find("t.name = N'O''Brien'", 1, true))
      assert.is_not_nil(sql:find('sys.computed_columns', 1, true))
      opts.on_stdout(nil, {
        'dbo|O\'Brien|Id|int|4|10|0|0|1|1|1||',
        'dbo|O\'Brien|Name|nvarchar|240|0|0|1|||0|(N\'unknown\')|',
        '(2 rows affected)',
      })
      opts.on_exit(nil, 0)
      return 1
    end
    data.fetch_create_script(conn, "O'Brien", function(script) received = script end)
    assert.is_true(vim.wait(200, function() return received ~= nil end, 10))
    assert.is_not_nil(received:find("CREATE TABLE [dbo].[O'Brien]", 1, true))
    assert.is_not_nil(received:find('[Id] int IDENTITY(1, 1) NOT NULL', 1, true))
    assert.is_not_nil(received:find("[Name] nvarchar(120) DEFAULT (N'unknown')", 1, true))
    assert.is_not_nil(received:find('PRIMARY KEY ([Id])', 1, true))
  end)

  it('loads only catalog dependencies on the selected table', function()
    local received
    vim.fn.jobstart = function(cmd, opts)
      local sql = cmd[#cmd]
      assert.is_not_nil(sql:find('sys.sql_expression_dependencies', 1, true))
      assert.is_not_nil(sql:find("SCHEMA_NAME(t.schema_id) = N'dbo'", 1, true))
      assert.is_not_nil(sql:find("t.name = N'Artists'", 1, true))
      opts.on_stdout(nil, { 'View|dbo.ArtistView', 'Function|dbo.ArtistCount', '(2 rows affected)' })
      opts.on_exit(nil, 0)
      return 1
    end
    data.fetch_references(conn, 'dbo.Artists', function(refs) received = refs end)
    assert.is_true(vim.wait(200, function() return received ~= nil end, 10))
    assert.same({
      { kind = 'View', name = 'dbo.ArtistView' },
      { kind = 'Function', name = 'dbo.ArtistCount' },
    }, received)
  end)

  it('recognizes saved query references without mistaking comments or longer names', function()
    vim.fn.readfile = function(path)
      if path:find('artist.sql', 1, true) then return { '-- Artists', 'SELECT * FROM dbo.Artists;' } end
      return { 'SELECT * FROM ArtistsArchive;', '/* Artists */' }
    end
    assert.same({ { kind = 'Saved Query', name = 'artist.sql', path = '/queries/artist.sql' } },
      data.saved_references({ '/queries/artist.sql', '/queries/archive.sql' }, 'Artists'))
    vim.fn.readfile = function() return { 'SELECT * FROM archive.Artists;' } end
    assert.same({}, data.saved_references({ '/queries/artist.sql' }, 'dbo.Artists'))
  end)

  it('fetches an object definition for opening, retaining its blank lines', function()
    local received
    vim.fn.jobstart = function(cmd, opts)
      assert.is_not_nil(cmd[#cmd]:find("OBJECT_ID(N'dbo.ArtistView')", 1, true))
      opts.on_stdout(nil, { '', 'CREATE VIEW dbo.ArtistView AS', '', 'SELECT 1;', '(1 row affected)' })
      opts.on_exit(nil, 0)
      return 1
    end
    data.fetch_definition(conn, 'dbo.ArtistView', function(definition) received = definition end)
    assert.is_true(vim.wait(200, function() return received ~= nil end, 10))
    assert.equals('CREATE VIEW dbo.ArtistView AS\n\nSELECT 1;', received)
  end)
end)
