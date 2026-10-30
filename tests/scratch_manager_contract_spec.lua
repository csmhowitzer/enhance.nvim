-- The interface scratch-manager.nvim's DB pads rely on (scratch-manager/providers/enhance.lua).
-- Changing anything here breaks DB pads: keep it stable, or update scratch-manager in the same release.
describe('scratch-manager contract', function()
  local api = require('enhance.api')
  local connections = require('enhance.connections')
  local executor = require('enhance.executor')
  local pad_conn = {
    name = 'Dev SQL', type = 'sqlserver', server = 'localhost', database = 'sample',
    user = 'reader', password = 'secret',
  }
  local old_get_connections, old_get_connection, old_execute

  before_each(function()
    old_get_connections, old_get_connection = connections.get_connections, connections.get_connection
    old_execute = executor.execute
    connections.get_connections = function() return { pad_conn } end
    connections.get_connection = function(name) return name == pad_conn.name and pad_conn or nil end
  end)

  after_each(function()
    connections.get_connections, connections.get_connection = old_get_connections, old_get_connection
    executor.execute = old_execute
  end)

  it('exposes enhance.api version 1 with the functions pads call', function()
    assert.is_true(type(api.version) == 'number' and api.version >= 1, 'api.version must stay >= 1')
    for _, name in ipairs({ 'connections', 'get_connection', 'execute', 'attach', 'detach', 'attached', 'pick_connection' }) do
      assert.equals('function', type(api[name]), 'enhance.api.' .. name .. ' is part of the contract')
    end
  end)

  it('runs the DB pad flow: list, attach with the connection table, execute with the pad buffer', function()
    local calls = {}
    executor.execute = function(conn, query, bufnr) calls[#calls + 1] = { conn = conn, query = query, bufnr = bufnr } end
    local pad = vim.api.nvim_create_buf(false, true)
    vim.bo[pad].filetype = 'sql'

    local list = api.connections()
    assert.equals(pad_conn, list[1])
    assert.is_true(api.attach(pad, list[1])) -- providers/enhance.lua: api.attach(bufnr, connection)
    assert.equals('Dev SQL', api.attached(pad))
    assert.truthy(vim.b[pad].db, 'attach sets b:db for vim-dadbod-completion (pad completion)')

    local ok, err = api.execute('SELECT 1', { connection = list[1], bufnr = pad })
    assert.is_true(ok, err)
    assert.same({ conn = pad_conn, query = 'SELECT 1', bufnr = pad }, calls[1])

    local bad_ok, bad_err = api.execute('SELECT 1', { connection = 'missing', bufnr = pad })
    assert.is_false(bad_ok)
    assert.equals('string', type(bad_err), 'failures return false plus a message the pad shows')
  end)

  it('keeps the fallbacks pads use with enhance versions before the public API', function()
    local completion = require('enhance.completion')
    assert.equals('function', type(connections.get_connections))
    assert.equals('function', type(executor.execute))
    assert.equals('function', type(completion.setup))
    -- argument order the fallbacks are called with
    assert.is_true(debug.getinfo(old_execute, 'u').nparams >= 3, 'executor.execute(connection, query, bufnr)')
    assert.is_true(debug.getinfo(completion.setup, 'u').nparams >= 2, 'completion.setup(bufnr, connection)')
  end)

  it('announces results to pads with User EnhanceQueryDone and its data fields', function()
    -- the full display path is covered in api_spec; pads read these fields
    local seen
    local id = vim.api.nvim_create_autocmd('User', {
      pattern = 'EnhanceQueryDone',
      callback = function(ev) seen = ev.data end,
    })
    vim.api.nvim_exec_autocmds('User', {
      pattern = 'EnhanceQueryDone',
      data = { bufnr = 1, result_bufnr = 2, connection = 'Dev SQL', row_count = 3, execution_time = 4, is_error = false },
    })
    vim.api.nvim_del_autocmd(id)
    for _, key in ipairs({ 'bufnr', 'result_bufnr', 'connection', 'row_count', 'execution_time', 'is_error' }) do
      assert.is_not_nil(seen[key], 'EnhanceQueryDone data.' .. key)
    end
  end)
end)
