describe('SQL Server structured query execution', function()
  local real_runner = require('enhance.helper_runner')
  local original, calls, owners, displayed, bufs
  local connection = { type = 'sqlserver', name = 'Test', server = 'unused', database = 'unused' }
  local function response()
    return { ok = true, parsed_result = { headers = { 'value', 'missing', 'empty' },
      rows = { { ' a|b\n雪 ', vim.NIL, '' } }, column_types = { 'nvarchar', 'int', 'varchar' },
      metadata = { db_type = 'sqlserver', transport = 'helper', protocol = 1 } },
      messages = {}, errors = {}, affected_rows = vim.NIL, duration_ms = 2 }
  end
  before_each(function()
    original = { runner = package.loaded['enhance.helper_runner'], results = package.loaded['enhance.results'],
      system = vim.fn.system, jobstart = vim.fn.jobstart, notify = vim.notify, config = package.loaded['enhance.config'] }
    calls, owners, displayed, bufs = {}, {}, {}, {}
    package.loaded['enhance.helper_runner'] = { new = function()
      local owner = {
        run = function(self, conn, sql, callback)
          self.callback = callback
          calls[#calls + 1] = { connection = conn, sql = sql, owner = self }
        end,
        cancel = function(self) self.cancelled = true; return true end,
      }
      owners[#owners + 1] = owner
      return owner
    end }
    package.loaded['enhance.results'] = {
      display = function(lines, conn, buf, metadata)
        displayed[#displayed + 1] = { lines = lines, connection = conn, buf = buf, metadata = metadata }
      end,
    }
    local function forbidden() error('query must not use CLI text or metadata probes') end
    vim.fn.system, vim.fn.jobstart, vim.notify = forbidden, forbidden, function() end
  end)
  after_each(function()
    local executor = require('enhance.executor')
    if executor.cancel_sqlserver then executor.cancel_sqlserver() end
    for _, buf in ipairs(bufs) do
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
    package.loaded['enhance.helper_runner'], package.loaded['enhance.results'] = original.runner, original.results
    package.loaded['enhance.config'] = original.config
    vim.fn.system, vim.fn.jobstart, vim.notify = original.system, original.jobstart, original.notify
  end)
  local function buffer()
    local buf = vim.api.nvim_create_buf(false, true)
    bufs[#bufs + 1] = buf
    return buf
  end

  it('routes the public SQL Server query path to one unchanged helper request', function()
    local sql = "  DECLARE @x int = 1; SELECT @x, 'a|b';\n-- keep\n"
    require('enhance.executor').execute(connection, sql)
    assert.equals(1, #calls)
    assert.equals(sql, calls[1].sql)
    assert.equals(connection, calls[1].connection)
    assert.equals(0, #displayed)
    calls[1].owner.callback(response())
    local metadata = displayed[1].metadata
    assert.equals(2, metadata.execution_time)
    assert.equals(1, metadata.row_count)
    assert.equals(vim.NIL, metadata.affected_rows)
    assert.are.same(response().parsed_result.rows, metadata.parsed_result.rows)
    assert.are.same({ 'nvarchar', 'int', 'varchar' }, metadata.result_rows[3].column_types)
    assert.is_true(metadata.result_rows[3].explicit_nulls)
  end)

  it('does not de-batch even independent statements across separate connections', function()
    local sql = 'SELECT 1; SELECT 2;'
    require('enhance.executor').execute_sqlserver(connection, sql)
    assert.equals(1, #calls)
    assert.equals(sql, calls[1].sql)
  end)

  it('does not use raw text when legacy format_results is false', function()
    package.loaded['enhance.config'] = { get = function() return false end }
    require('enhance.executor').execute_sqlserver(connection, 'SELECT 1')
    calls[1].owner.callback(response())
    assert.are.same(response().parsed_result.rows, displayed[1].metadata.parsed_result.rows)
    assert.is_true(displayed[1].metadata.result_rows[3].explicit_nulls)
  end)

  it('retains multiple and empty result sets with native positional type metadata', function()
    local value = response()
    value.parsed_result = { multiple_results = true, result_sets = { value.parsed_result,
      { headers = { 'empty' }, rows = {}, column_types = { 'date' }, metadata = { transport = 'helper' } } },
      metadata = { transport = 'helper' } }
    require('enhance.executor').execute_sqlserver(connection, 'SELECT 1; SELECT 2 WHERE 1=0;')
    calls[1].owner.callback(value)
    assert.equals(2, #displayed[1].metadata.parsed_result.result_sets)
    assert.equals(1, displayed[1].metadata.row_count)
    assert.is_truthy(table.concat(displayed[1].lines, '\n'):find('Result Set 2/2', 1, true))
  end)

  it('displays SQL errors and retained earlier rows without mislabeling them as success', function()
    local value = response()
    value.ok = false
    value.errors = { { kind = 'sql_error', message = 'Invalid object name', number = 208, severity = 16, state = 1, line = 2 } }
    value.messages = { { message = 'before failure', number = 0, severity = 0, state = 1, line = 1 } }
    require('enhance.executor').execute_sqlserver(connection, 'SELECT 1; SELECT * FROM missing;')
    calls[1].owner.callback(value)
    assert.is_true(displayed[1].metadata.is_error)
    assert.are.same(value.errors, displayed[1].metadata.errors)
    assert.are.same(value.messages, displayed[1].metadata.messages)
    assert.are.same(value.parsed_result.rows, displayed[1].metadata.parsed_result.rows)
    local text = table.concat(displayed[1].lines, '\n')
    assert.is_truthy(text:find('Msg 208', 1, true))
    assert.is_truthy(text:find('before failure', 1, true))
  end)

  it('displays aggregate DML counts separately from returned table rows', function()
    local value = response()
    value.parsed_result = { headers = {}, rows = {}, metadata = { transport = 'helper' } }
    value.affected_rows = 7
    require('enhance.executor').execute_sqlserver(connection, 'UPDATE t SET x=1;')
    calls[1].owner.callback(value)
    assert.equals(0, displayed[1].metadata.row_count)
    assert.equals(7, displayed[1].metadata.affected_rows)
    assert.is_truthy(table.concat(displayed[1].lines, '\n'):find('Rows affected: 7', 1, true))
  end)

  it('displays a missing-helper failure without falling back to sqlcmd', function()
    require('enhance.executor').execute_sqlserver(connection, 'SELECT 1')
    calls[1].owner.callback(nil, 'SQL Server helper unavailable; rebuild enhance.nvim in lazy.nvim')
    assert.is_true(displayed[1].metadata.is_error)
    assert.is_truthy(table.concat(displayed[1].lines, '\n'):find('helper unavailable', 1, true))
  end)

  for _, case in ipairs({ { 208, 'Invalid object name' }, { 102, 'Incorrect syntax' },
    { 2627, 'PRIMARY KEY constraint' }, { 2714, 'There is already an object' } }) do
    it('preserves structured SQL error ' .. case[1] .. ' and its diagnostic text', function()
      local value = response()
      value.ok = false
      value.errors = { { kind = 'sql_error', number = case[1], message = case[2], severity = 16, state = 1, line = 2 } }
      require('enhance.executor').execute_sqlserver(connection, 'SELECT 1')
      calls[1].owner.callback(value)
      assert.is_true(displayed[1].metadata.is_error)
      local text = table.concat(displayed[1].lines, '\n')
      assert.is_truthy(text:find('Msg ' .. case[1], 1, true))
      assert.is_truthy(text:find(case[2], 1, true))
    end)
  end

  it('runs the public executor through a real process and decoder into formatted raw-value metadata', function()
    local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    package.loaded['enhance.helper_runner'] = { new = function()
      return real_runner._new({
        resolve = function() return root .. '/tests/fixtures/helper_process.py' end,
        spawn = function(cmd, opts, callback) return vim.system({ 'python3', cmd[1] }, opts, callback) end,
        schedule = vim.schedule,
      })
    end }
    local buf = buffer()
    local sql = "  SELECT '雪|a\r\n\0';\n-- keep  " .. string.rep('x', 10000)
    require('enhance.executor').execute(connection, sql, buf)
    assert.is_true(vim.wait(5000, function() return #displayed > 0 end, 10))
    local metadata = displayed[1].metadata
    assert.is_false(metadata.is_error)
    assert.equals(sql, metadata.parsed_result.rows[1][1])
    assert.equals(vim.NIL, metadata.parsed_result.rows[1][2])
    assert.equals(sql, metadata.result_rows[3].values[1])
    assert.is_true(metadata.result_rows[3].explicit_nulls)
  end)

  it('reuses one owner per query buffer and exposes cancellation', function()
    local buf = buffer()
    local executor = require('enhance.executor')
    executor.execute_sqlserver(connection, 'SELECT 1', buf)
    executor.execute_sqlserver(connection, 'SELECT 2', buf)
    assert.equals(calls[1].owner, calls[2].owner)
    assert.is_true(executor.cancel_sqlserver(buf))
    assert.is_true(calls[1].owner.cancelled)
  end)

  it('does not render stale callbacks from superseded executions', function()
    local buf = buffer()
    local executor = require('enhance.executor')
    executor.execute_sqlserver(connection, 'SELECT 1', buf)
    local first = calls[1].owner.callback
    executor.execute_sqlserver(connection, 'SELECT 2', buf)
    first(response())
    assert.equals(0, #displayed)
    calls[2].owner.callback(response())
    assert.equals(1, #displayed)
  end)

  it('cancels and discards results when the query buffer is wiped', function()
    local buf = buffer()
    require('enhance.executor').execute_sqlserver(connection, 'SELECT 1', buf)
    local owner = calls[1].owner
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_true(owner.cancelled)
    owner.callback(response())
    assert.equals(0, #displayed)
  end)

  it('keeps query buffers independent and refuses deleted buffers before starting', function()
    local one, two = buffer(), buffer()
    local executor = require('enhance.executor')
    executor.execute_sqlserver(connection, 'SELECT 1', one)
    executor.execute_sqlserver(connection, 'SELECT 2', two)
    assert.not_equals(calls[1].owner, calls[2].owner)
    vim.api.nvim_buf_delete(one, { force = true })
    executor.execute_sqlserver(connection, 'SELECT 3', one)
    assert.equals(2, #calls)
  end)

  it('cancels and detaches all owners on editor shutdown', function()
    local executor = require('enhance.executor')
    executor.execute_sqlserver(connection, 'SELECT 1', buffer())
    executor.execute_sqlserver(connection, 'SELECT 2', buffer())
    local first, second = calls[1].owner, calls[2].owner
    vim.api.nvim_exec_autocmds('VimLeavePre', { group = 'EnhanceSQLServerQueries' })
    assert.is_true(first.cancelled)
    assert.is_true(second.cancelled)
    first.callback(response()); second.callback(response())
    assert.equals(0, #displayed)
  end)
end)
