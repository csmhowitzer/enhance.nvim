describe('synchronous structured query timeout', function()
  it('gives each backend four minutes for the command plus connection/grace time', function()
    local installer = require('enhance.helper_install')
    local original_path, original_system = installer.path, vim.system
    local response = vim.json.encode({ protocol = 1, ok = true, resultSets = {},
      messages = {}, errors = {}, affectedRows = vim.NIL, durationMs = 1 })
    local requests = {}
    installer.path = function() return '/verified/helper' end
    vim.system = function(_, opts)
      requests[#requests + 1] = opts
      return { wait = function() return { code = 0, signal = 0, stdout = response } end }
    end
    local ok, err = pcall(function()
      for _, db in ipairs({ 'sqlserver', 'mysql', 'postgresql' }) do
        local parsed, query_error = require('enhance.db.helper_sync').execute(db,
          { server = 'local', database = 'sample', user = 'reader' }, 'SELECT 1;')
        assert.is_nil(query_error)
        assert.is_not_nil(parsed)
      end
      assert.equals(3, #requests)
      for _, request in ipairs(requests) do
        assert.equals(240, vim.json.decode(request.stdin).commandTimeoutSeconds)
        assert.equals(260000, request.timeout)
      end
    end)
    installer.path, vim.system = original_path, original_system
    if not ok then error(err) end
  end)
end)

describe('interactive connection probes', function()
  it('starts a network probe asynchronously and reports CLI errors', function()
    local cli = require('enhance.db.cli_credentials')
    local old_async, pending, result = cli.system_async, nil, nil
    cli.system_async = function(cmd, _, _, callback)
      assert.matches('SELECT 1;', table.concat(cmd, ' '), 1, true)
      pending = callback
    end
    local ok, err = pcall(function()
      require('enhance.executor').test_connection_async({ type = 'mysql', host = 'local', database = 'demo' },
        function(success, message) result = { success, message } end)
      assert.is_nil(result)
      pending('CLI unavailable', -1)
      assert.is_false(result[1])
      assert.matches('CLI unavailable', result[2], 1, true)
    end)
    cli.system_async = old_async
    if not ok then error(err) end
  end)
end)

describe('SQLite query timeout', function()
  it('bounds explicit synchronous SQLite statements to four minutes', function()
    local original_system = vim.system
    local deadline
    vim.system = function(_, opts)
      deadline = opts.timeout
      return { wait = function() return { code = 124, stdout = '', stderr = 'timed out' } end }
    end
    local ok, err = pcall(function()
      local _, query_error = require('enhance.db.sqlite').execute_single({ path = ':memory:' }, 'SELECT 1;')
      assert.equals(240000, deadline)
      assert.is_not_nil(query_error)
    end)
    vim.system = original_system
    if not ok then error(err) end
  end)

  it('stops an asynchronous SQLite batch only after the four-minute deadline', function()
    local original_readable, original_jobstart = vim.fn.filereadable, vim.fn.jobstart
    local original_jobstop, original_defer, original_notify = vim.fn.jobstop, vim.defer_fn, vim.notify
    local results = require('enhance.results')
    local original_display = results.display
    local deadline, fire, stopped, job_opts, displayed
    vim.fn.filereadable = function() return 1 end
    vim.fn.jobstart = function(_, opts) job_opts = opts; return 99 end
    vim.fn.jobstop = function(job)
      stopped = job
      job_opts.on_exit(nil, 0)
      return 1
    end
    vim.defer_fn = function(callback, ms)
      fire, deadline = callback, ms
      return { stop = function() end, close = function() end, is_closing = function() return false end }
    end
    vim.notify = function() end
    results.display = function(lines, _, _, metadata) displayed = { lines = lines, metadata = metadata } end
    local ok, err = pcall(function()
      require('enhance.executor').execute_sqlite({ type = 'sqlite', path = ':memory:' }, 'SELECT 1;')
      assert.equals(240000, deadline)
      assert.is_nil(stopped)
      fire()
      assert.equals(99, stopped)
      assert.is_true(displayed.metadata.is_error)
      assert.matches('SQLite query timed out after 240 seconds', table.concat(displayed.lines, '\n'), 1, true)
    end)
    vim.fn.filereadable, vim.fn.jobstart, vim.fn.jobstop = original_readable, original_jobstart, original_jobstop
    vim.defer_fn, vim.notify = original_defer, original_notify
    results.display = original_display
    if not ok then error(err) end
  end)

  it('reports a missing SQLite executable rather than leaving results pending', function()
    local old_readable, old_jobstart, old_notify = vim.fn.filereadable, vim.fn.jobstart, vim.notify
    local results = require('enhance.results')
    local old_display, displayed = results.display
    vim.fn.filereadable = function() return 1 end
    vim.fn.jobstart = function() return -1 end
    vim.notify = function() end
    results.display = function(lines, _, _, metadata) displayed = { lines = lines, metadata = metadata } end
    local ok, err = pcall(function()
      require('enhance.executor').execute_sqlite({ type = 'sqlite', path = ':memory:' }, 'SELECT 1;')
      assert.is_true(displayed.metadata.is_error)
      assert.matches('Failed to start SQLite', table.concat(displayed.lines, '\n'), 1, true)
    end)
    vim.fn.filereadable, vim.fn.jobstart, vim.notify = old_readable, old_jobstart, old_notify
    results.display = old_display
    if not ok then error(err) end
  end)

  it('starts SQLite de-batched work without blocking and preserves partial results', function()
    local sqlite = require('enhance.db.sqlite')
    local old_async, old_notify, old_readable = sqlite.execute_single_async, vim.notify, vim.fn.filereadable
    local results = require('enhance.results')
    local old_display, pending, queries, displayed = results.display, {}, {}, nil
    sqlite.execute_single_async = function(_, sql, callback)
      queries[#queries + 1] = sql
      pending[#pending + 1] = callback
    end
    vim.notify = function() end
    vim.fn.filereadable = function() return 1 end
    results.display = function(_, _, _, metadata) displayed = metadata end
    local ok, err = pcall(function()
      require('enhance.executor').execute_sqlite({ type = 'sqlite', path = ':memory:' },
        'UPDATE t SET x=1; UPDATE t SET x=2;')
      assert.equals(1, #pending)
      pending[1]({ headers = { 'x' }, rows = { { '1' } } }, nil, 1, 1)
      assert.equals(2, #pending)
      pending[2](nil, 'SQLite failure', 2, 0)
      assert.equals(2, #queries)
      assert.is_true(displayed.is_error)
      assert.equals(2, #displayed.statement_results)
      assert.equals(1, displayed.statement_results[1].rows)
    end)
    sqlite.execute_single_async, vim.notify, vim.fn.filereadable = old_async, old_notify, old_readable
    results.display = old_display
    if not ok then error(err) end
  end)

  it('cancels a superseded SQLite de-batch and ignores its late result', function()
    local sqlite = require('enhance.db.sqlite')
    local old_async, old_notify, old_readable = sqlite.execute_single_async, vim.notify, vim.fn.filereadable
    local results = require('enhance.results')
    local old_display, pending, cancelled, displays = results.display, {}, 0, 0
    vim.fn.filereadable = function() return 1 end
    vim.notify = function() end
    sqlite.execute_single_async = function(_, _, callback)
      pending[#pending + 1] = callback
      return { kill = function() cancelled = cancelled + 1 end }
    end
    results.display = function() displays = displays + 1 end
    local ok, err = pcall(function()
      local executor = require('enhance.executor')
      executor.execute_sqlite({ type = 'sqlite', path = ':memory:' }, 'UPDATE t SET x=1; UPDATE t SET x=2;')
      executor.execute_sqlite({ type = 'sqlite', path = ':memory:' }, 'UPDATE t SET x=3; UPDATE t SET x=4;')
      assert.equals(1, cancelled)
      pending[1]({ rows = {} }, nil, 1, 0)
      assert.equals(2, #pending)
      pending[2](nil, 'failed', 1, 0)
      assert.equals(1, displays)
    end)
    sqlite.execute_single_async, vim.notify, vim.fn.filereadable = old_async, old_notify, old_readable
    results.display = old_display
    if not ok then error(err) end
  end)
end)
