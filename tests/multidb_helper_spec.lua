describe('structured MySQL and PostgreSQL execution', function()
  local boundary = require('enhance.db.sqlserver_helper')
  for _, db in ipairs({ 'mysql', 'mariadb', 'postgres', 'postgresql' }) do
    it('encodes unchanged ' .. db .. ' SQL with a separate endpoint port', function()
      local sql = "  SELECT 'a|b;--c';\nSELECT 2; "
      local body, err = boundary.encode_request({ type = db, host = 'localhost', port = 5544,
        database = 'db', user = 'reader', password = '', ssl_mode = 'disable' }, sql)
      assert.is_nil(err)
      local request = vim.json.decode(body)
      assert.equals(db:match('postgres') and 'postgresql' or 'mysql', request.dbType)
      assert.equals('localhost', request.connection.server)
      assert.equals(5544, request.connection.port)
      assert.equals(sql, request.query)
      assert.equals('disable', request.connection.sslMode)
    end)

    it('uses one helper request on the public ' .. db .. ' query path, never CLI parsing', function()
      local old_runner, old_results, old_job, old_notify = package.loaded['enhance.helper_runner'],
        package.loaded['enhance.results'], vim.fn.jobstart, vim.notify
      local call, rendered
      package.loaded['enhance.helper_runner'] = { new = function()
        return { run = function(_, conn, sql, callback) call = { conn, sql, callback } end,
          cancel = function() return true end }
      end }
      package.loaded['enhance.results'] = { display = function(_, _, _, metadata) rendered = metadata end }
      vim.fn.jobstart = function() error('ambiguous CLI query execution is forbidden') end
      vim.notify = function() end
      local ok, err = pcall(function()
        local conn = { type = db, host = 'unused', database = 'unused' }
        local sql = " SELECT 'a|b'; SELECT '雪'; "
        require('enhance.executor').execute(conn, sql)
        assert.equals(conn, call[1]); assert.equals(sql, call[2])
        call[3]({ ok = true, parsed_result = { headers = { 'same', 'same', '' },
          rows = { { 'a|b\n雪', vim.NIL, '' } }, column_types = { 'text', 'text', 'text' },
          metadata = { transport = 'helper' } }, messages = {}, errors = {},
          duration_ms = 1, affected_rows = vim.NIL })
        assert.equals(vim.NIL, rendered.parsed_result.rows[1][2])
        assert.equals('', rendered.parsed_result.rows[1][3])
        assert.is_true(rendered.result_rows[3].explicit_nulls)
      end)
      if require('enhance.executor').cancel_query then require('enhance.executor').cancel_query() end
      package.loaded['enhance.helper_runner'], package.loaded['enhance.results'] = old_runner, old_results
      vim.fn.jobstart, vim.notify = old_job, old_notify
      assert.is_true(ok, tostring(err))
    end)
  end

  it('preserves PostgreSQL backend identity and SQLSTATE on decoding', function()
    local value = { protocol = 1, ok = false, resultSets = { { columns = { { name = '', type = 'oid:25', format = 0 } },
      rows = { { 'literal|text' } } } }, messages = {}, errors = {
      { kind = 'sql_error', message = 'missing', sqlState = '42P01' } }, affectedRows = vim.NIL, durationMs = 1 }
    local response = boundary.decode_response(vim.json.encode(value), 1, 'postgresql')
    assert.equals('postgresql', response.parsed_result.metadata.db_type)
    assert.equals('42P01', response.errors[1].sqlState)
    assert.are.same({ 0 }, response.parsed_result.column_formats)
  end)

  it('runs the native PostgreSQL wire-protocol regressions through nvt', function()
    local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    local output = vim.fn.system({ 'go', '-C', root .. '/helper-postgres', 'test', './...' })
    assert.equals(0, vim.v.shell_error, output)
  end)
end)
