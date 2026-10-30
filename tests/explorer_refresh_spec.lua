-- Connect/disconnect redraw the explorer without dropping caches or killing catalog lookups, and the
-- explorer never forces a full-screen redraw.
describe('explorer refresh', function()
  local connections = require('enhance.connections')

  local function fake_explorer(calls)
    return {
      is_initialized = function() return true end,
      is_open = function() return false end,
      collapse_connection = function(name) calls[#calls + 1] = 'collapse ' .. name end,
      refresh_explorer = function() calls[#calls + 1] = 'redraw' end,
      refresh = function() calls[#calls + 1] = 'refresh' end,
      show_dashboard = function() end,
    }
  end

  local saved
  before_each(function()
    saved = { package.loaded['enhance.explorer'], vim.notify }
  end)
  after_each(function()
    package.loaded['enhance.explorer'], vim.notify = saved[1], saved[2]
  end)

  it('disconnect redraws only, without a warning when the explorer is hidden', function()
    local calls, warnings = {}, {}
    package.loaded['enhance.explorer'] = fake_explorer(calls)
    vim.notify = function(msg, level) if level == vim.log.levels.WARN then warnings[#warnings + 1] = msg end end
    connections.set_current({ name = 'Dev', type = 'sqlite', path = ':memory:' })
    calls = {}
    package.loaded['enhance.explorer'] = fake_explorer(calls)
    connections.disconnect()
    assert.same({ 'collapse Dev', 'redraw' }, calls)
    assert.same({}, warnings)
  end)

  it('a successful async connect redraws only (keeps the lookups set_current started)', function()
    local calls = {}
    package.loaded['enhance.explorer'] = fake_explorer(calls)
    vim.notify = function() end
    local executor = require('enhance.executor')
    local old = executor.test_connection_async
    executor.test_connection_async = function(_, cb) cb(true) end
    connections.connect_async({ name = 'Dev', type = 'sqlite', path = ':memory:' })
    executor.test_connection_async = old
    assert.is_nil(vim.tbl_contains(calls, 'refresh') and true or nil, 'connect must not call refresh()')
    assert.is_true(vim.tbl_contains(calls, 'redraw'))
    connections.disconnect()
  end)

  it('redrawing the explorer never forces redraw or redraw!', function()
    package.loaded['enhance.explorer'] = saved[1]
    local explorer = require('enhance.explorer')
    vim.notify = function() end
    assert.is_true(pcall(explorer.start))
    assert.is_true(explorer.is_open(), 'the explorer must be open so the redraw path runs')
    local old_cmd, forced = vim.cmd, false
    vim.cmd = setmetatable({}, {
      __call = function(_, c) if type(c) == 'string' and c:match('^redraw') then forced = true end return old_cmd(c) end,
      __index = function(_, k) return old_cmd[k] end,
    })
    local ok, err = pcall(explorer.refresh_explorer)
    vim.cmd = old_cmd
    pcall(explorer.stop)
    assert.is_true(ok, err)
    assert.is_false(forced)
  end)
end)
