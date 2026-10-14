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
end)
