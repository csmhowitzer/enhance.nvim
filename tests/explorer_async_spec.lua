describe('explorer catalog responsiveness', function()
  it('starts table discovery once, renders immediately, and fills the cache after completion', function()
    local connections = require('enhance.connections')
    local original_connections = connections.get_connections
    local original_current = connections.get_current
    local old_system, old_schedule = vim.system, vim.schedule
    local explorer = require('enhance.explorer')
    local old_is_open = explorer.is_open
    local calls, finish = 0, nil
    connections.get_connections = function()
      return { { name = 'C08 async fixture', type = 'sqlite', path = ':memory:' } }
    end
    connections.get_current = function() return nil end
    explorer.is_open = function() return false end
    vim.system = function(_, opts, callback)
      calls = calls + 1
      assert.equals(30000, opts.timeout)
      finish = callback
      return { kill = function() end }
    end
    vim.schedule = function(fn) fn() end
    local ok, err = pcall(function()
      local conn = connections.get_connections()[1]
      assert.same({}, explorer._fetch_tables(conn, nil, true))
      assert.equals(1, calls)
      assert.same({}, explorer._fetch_tables(conn, nil, true))
      assert.equals(1, calls)
      finish({ code = 0, stdout = 'artists\nalbums\n' })
      assert.same({ 'artists', 'albums' }, explorer._fetch_tables(conn, nil, true))
      assert.equals(1, calls)
    end)
    vim.system, vim.schedule = old_system, old_schedule
    connections.get_connections, connections.get_current = original_connections, original_current
    explorer.is_open = old_is_open
    if not ok then error(err) end
  end)

  it('invalidates a pending catalog lookup on refresh and ignores its late answer', function()
    local explorer = require('enhance.explorer')
    local old_system, old_schedule, old_is_open, old_notify = vim.system, vim.schedule, explorer.is_open, vim.notify
    local finish, killed, calls = nil, false, 0
    explorer.is_open = function() return true end
    vim.notify = function() end
    vim.schedule = function(fn) fn() end
    vim.system = function(_, _, callback)
      finish, calls = callback, calls + 1
      return { kill = function() killed = true end }
    end
    local ok, err = pcall(function()
      local conn = { name = 'C08 refresh fixture', type = 'sqlite', path = ':memory:' }
      explorer._fetch_tables(conn, nil, true)
      local old_finish = finish
      explorer.refresh()
      assert.is_true(killed)
      old_finish({ code = 0, stdout = 'stale\n' })
      assert.same({}, explorer._fetch_tables(conn, nil, true))
      assert.equals(2, calls)
      finish({ code = 0, stdout = 'fresh\n' })
      assert.same({ 'fresh' }, explorer._fetch_tables(conn, nil, true))
    end)
    vim.system, vim.schedule, vim.notify, explorer.is_open = old_system, old_schedule, old_notify, old_is_open
    if not ok then error(err) end
  end)
end)
