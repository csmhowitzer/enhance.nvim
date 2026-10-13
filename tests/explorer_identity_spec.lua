describe('explorer schema-qualified object identity', function()
  local explorer, cli, original_system, queries

  before_each(function()
    package.loaded['enhance.explorer'] = nil
    explorer = require('enhance.explorer')
    cli = require('enhance.db.cli_credentials')
    original_system = cli.system
    queries = {}
    cli.system = function(cmd)
      local query
      for index, value in ipairs(cmd) do
        if value == '-Q' or value == '-c' or value == '-e' then query = cmd[index + 1]; break end
      end
      queries[#queries + 1] = query
      return '[dbo].[Artists]\n[archive].[Artists]\n[Odd]]Schema].[select name]\n', 0
    end
  end)

  after_each(function() cli.system = original_system end)

  it('discovers separate SQL Server schemas and escapes names in list, metadata, and write templates', function()
    local conn = { name = 'C06-sqlserver', type = 'sqlserver', server = 'local', database = 'sample' }
    assert.same({ '[dbo].[Artists]', '[archive].[Artists]', '[Odd]]Schema].[select name]' },
      explorer._fetch_tables(conn, true))
    assert.matches('TABLE_SCHEMA', queries[1], 1, true)
    assert.matches('QUOTENAME', queries[1], 1, true)
    local name = '[Odd]]Schema].[select name]'
    assert.matches('FROM [Odd]]Schema].[select name]', explorer._generate_metadata_query(conn, name, 'table_list'), 1, true)
    local columns = explorer._generate_metadata_query(conn, name, 'table_columns')
    assert.matches("TABLE_SCHEMA = N'Odd]Schema'", columns, 1, true)
    assert.matches("TABLE_NAME = N'select name'", columns, 1, true)
    assert.matches('DROP TABLE [Odd]]Schema].[select name];',
      explorer._generate_table_script(conn, name, 'table_drop'), 1, true)
    assert.matches('DELETE FROM [Odd]]Schema].[select name]',
      explorer._generate_table_script(conn, name, 'table_delete_records'), 1, true)
  end)

  it('escapes quote characters in metadata filters and keeps same-named objects separate', function()
    local conn = { type = 'sqlserver' }
    local name = "[archive].[O'Brien]"
    local query = explorer._generate_metadata_query(conn, name, 'table_indexes')
    assert.matches("OBJECT_ID(N'[archive].[O''Brien]')", query, 1, true)
    assert.matches('[dbo].[Artists]', explorer._generate_metadata_query(conn, '[dbo].[Artists]', 'table_list'), 1, true)
    assert.matches('[archive].[Artists]', explorer._generate_metadata_query(conn, '[archive].[Artists]', 'table_list'), 1, true)
  end)

  it('quotes PostgreSQL and MySQL table identifiers, including reserved words and dots', function()
    local pg = { name = 'C06-pg', type = 'postgresql', database = 'sample' }
    cli.system = function(cmd)
      queries[#queries + 1] = cmd[#cmd]
      return '"public"."Artists"\n"other"."Artists"\n"other"."O""Brien"\n', 0
    end
    assert.same({ '"public"."Artists"', '"other"."Artists"', '"other"."O""Brien"' },
      explorer._fetch_tables(pg, true))
    assert.matches('schemaname', queries[1], 1, true)
    assert.matches('"other"."O""Brien"',
      explorer._generate_metadata_query(pg, '"other"."O""Brien"', 'table_list'), 1, true)
    local columns = explorer._generate_metadata_query(pg, '"other"."O""Brien"', 'table_columns')
    assert.matches("table_schema = 'other'", columns, 1, true)
    assert.matches("table_name = 'O\"Brien'", columns, 1, true)
    local mysql = { name = 'C06-mysql', type = 'mysql', database = 'sample' }
    cli.system = function() return 'select name\nweird`name\na.b\n', 0 end
    assert.same({ '`select name`', '`weird``name`', '`a.b`' }, explorer._fetch_tables(mysql, true))
    assert.matches('FROM `a.b`', explorer._generate_metadata_query(mysql, '`a.b`', 'table_list'), 1, true)
  end)

  it('quotes SQLite names and resolves qualified SQL Server definitions by full identity', function()
    local sqlite = { type = 'sqlite' }
    assert.equals('SELECT * FROM "select name" LIMIT 200;',
      explorer._generate_metadata_query(sqlite, 'select name', 'table_list'))
    assert.matches("name='O''Brien'",
      explorer._generate_metadata_query(sqlite, "O'Brien", 'table_create'), 1, true)
    local conn = { type = 'sqlserver', server = 'local', database = 'sample' }
    explorer._fetch_definition_script(conn, '[archive].[Artist View]', 'view_create')
    assert.matches('OBJECT_ID', queries[#queries], 1, true)
    assert.matches('[archive].[Artist View]', queries[#queries], 1, true)
  end)

  it('carries distinct same-named SQL Server tables through explorer rows and actions', function()
    local buf = vim.api.nvim_create_buf(false, true)
    local rows = {
      'Database Explorer',
      '',
      '✗ ▾ 󰆼 C06',
      '    ▾ 󰓱  Tables (2)',
      '      ▾ 󰓫  [dbo].[Artists]',
      '          󰆼  DROP Table',
      '      ▾ 󰓫  [archive].[Artists]',
      '          󰆼  DROP Table',
      '      ▾ 󰓫  [odd].[Tables]',
      '          󰆼  DELETE Records',
    }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
    explorer._set_explorer_buf(buf)
    assert.equals('[dbo].[Artists]', explorer._parse_line(rows[6], 6).table_name)
    assert.equals('[archive].[Artists]', explorer._parse_line(rows[8], 8).table_name)
    assert.equals('[odd].[Tables]', explorer._parse_line(rows[9], 9).table_name)
    assert.equals('table_delete_records', explorer._parse_line(rows[10], 10).type)
    explorer._set_explorer_buf(nil)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('targets qualified views and routines, escaping bracket and apostrophe characters', function()
    local identity = require('enhance.db.object_identity')
    local conn = { type = 'sqlserver' }
    local label = "[O'Brien].[a]]b]"
    assert.same({ "O'Brien", 'a]b' }, { identity.parts(label, 'sqlserver') })
    local view_drop = explorer._generate_object_script(conn, label, 'view_drop')
    assert.matches("DROP VIEW [O'Brien].[a]]b];", view_drop, 1, true)
    local params = explorer._generate_object_script(conn, label, 'proc_params')
    assert.matches("SPECIFIC_SCHEMA = N'O''Brien' AND SPECIFIC_NAME = N'a]b'", params, 1, true)
    local exec = explorer._generate_object_script(conn, label, 'proc_execute')
    assert.matches("EXEC [O'Brien].[a]]b]", exec, 1, true)
  end)

  it('scopes catalog-generated CREATE and UPDATE templates to the selected schema', function()
    for _, case in ipairs({
      { type = 'sqlserver', label = '[archive].[Artists]', schema = 'TABLE_SCHEMA = N\'archive\'',
        escaped_column = 'QUOTENAME(COLUMN_NAME)' },
      { type = 'postgresql', label = '"archive"."Artists"', schema = "table_schema = 'archive'",
        escaped_column = 'quote_ident(column_name)' },
      { type = 'mysql', label = '`archive`.`Artists`', schema = "TABLE_SCHEMA = 'archive'",
        escaped_column = "REPLACE(COLUMN_NAME, '`', '``')" },
    }) do
      local conn = { type = case.type, database = 'sample' }
      local create = explorer._generate_metadata_query(conn, case.label, 'table_create')
      local update = explorer._generate_metadata_query(conn, case.label, 'table_update')
      if case.type == 'mysql' then
        assert.equals('SHOW CREATE TABLE `archive`.`Artists`;', create)
      else
        assert.matches(case.schema, create, 1, true)
      end
      assert.matches(case.schema, update, 1, true)
      assert.matches(case.escaped_column, update, 1, true)
    end
  end)
end)
