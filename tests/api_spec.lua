describe('enhance.api', function()
  local api = require('enhance.api')
  local connections = require('enhance.connections')
  local sqlserver = {
    name = 'Dev SQL', type = 'sqlserver', server = 'localhost', database = 'sample',
    user = 'reader', password = 'secret',
  }
  local sqlite = { name = 'Local SQLite', type = 'sqlite', path = ':memory:' }
  local old_get_connections, old_get_connection

  before_each(function()
    old_get_connections, old_get_connection = connections.get_connections, connections.get_connection
    connections.get_connections = function() return { sqlserver, sqlite } end
    connections.get_connection = function(name)
      for _, conn in ipairs({ sqlserver, sqlite }) do
        if conn.name == name then return conn end
      end
    end
  end)

  after_each(function()
    connections.get_connections, connections.get_connection = old_get_connections, old_get_connection
  end)

  local function sql_buffer()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = 'sql'
    return buf
  end

  it('lists and finds connections', function()
    assert.equals(2, #api.connections())
    assert.equals(sqlite, api.get_connection('Local SQLite'))
    assert.is_nil(api.get_connection('missing'))
    assert.equals(1, api.version)
  end)

  it('executes by connection name or table, passing the source buffer along', function()
    local executor = require('enhance.executor')
    local old_execute, calls = executor.execute, {}
    executor.execute = function(conn, query, bufnr) calls[#calls + 1] = { conn = conn, query = query, bufnr = bufnr } end
    local ok_name = api.execute('SELECT 1', { connection = 'Dev SQL', bufnr = 7 })
    local ok_table = api.execute('SELECT 2', { connection = sqlite })
    executor.execute = old_execute

    assert.is_true(ok_name)
    assert.is_true(ok_table)
    assert.same({ conn = sqlserver, query = 'SELECT 1', bufnr = 7 }, calls[1])
    assert.equals(sqlite, calls[2].conn)
  end)

  it('rejects empty queries and unknown connections without running', function()
    local executor = require('enhance.executor')
    local old_execute, ran = executor.execute, false
    executor.execute = function() ran = true end
    local ok_empty, err_empty = api.execute('   ', { connection = 'Dev SQL' })
    local ok_unknown, err_unknown = api.execute('SELECT 1', { connection = 'nope' })
    local ok_missing = api.execute('SELECT 1', {})
    executor.execute = old_execute

    assert.is_false(ok_empty)
    assert.truthy(err_empty:find('No query'))
    assert.is_false(ok_unknown)
    assert.truthy(err_unknown:find('Unknown enhance connection'))
    assert.is_false(ok_missing)
    assert.is_false(ran)
  end)

  it('attaches completion to any SQL buffer without registering it in the explorer', function()
    local buf = sql_buffer()
    assert.is_true(api.attach(buf, 'Dev SQL'))
    assert.equals('Dev SQL', api.attached(buf))
    assert.truthy(vim.b[buf].db:find('^sqlserver://localhost/sample'))
    assert.equals('vim_dadbod_completion#omni', vim.bo[buf].omnifunc)
    assert.is_nil(vim.b[buf].enhance_connection)

    api.detach(buf)
    assert.is_nil(api.attached(buf))
    assert.is_nil(vim.b[buf].db)
    assert.equals('', vim.bo[buf].omnifunc)
  end)

  it('attaches to non-SQL Server connections without completion', function()
    local buf = sql_buffer()
    assert.is_true(api.attach(buf, sqlite))
    assert.equals('Local SQLite', api.attached(buf))
    assert.is_nil(vim.b[buf].db)
    assert.is_false((api.attach(buf, 'nope')))
  end)

  it('picks a connection with vim.ui.select', function()
    local old_select, chosen = vim.ui.select, nil
    vim.ui.select = function(items, opts, cb)
      assert.equals('Dev SQL (sqlserver)', opts.format_item(items[1]))
      cb(items[2])
    end
    api.pick_connection(function(conn) chosen = conn end)
    vim.ui.select = old_select
    assert.equals(sqlite, chosen)
  end)

  it('announces displayed results with User EnhanceQueryDone', function()
    local results = require('enhance.results')
    local old_explorer, old_schedule, old_notify = package.loaded['enhance.explorer'], vim.schedule, vim.notify
    local query = vim.api.nvim_create_buf(false, true)
    local buf = vim.api.nvim_create_buf(false, true)
    package.loaded['enhance.explorer'] = {
      get_result_buffer_info = function() return buf end,
      associate_result_buffer = function() end,
      get_results_window = function() return vim.api.nvim_get_current_win() end,
      set_results_window = function() end,
      refresh_explorer = function() end,
    }
    vim.schedule = function() end
    vim.notify = function() end
    local seen
    local id = vim.api.nvim_create_autocmd('User', {
      pattern = 'EnhanceQueryDone',
      callback = function(ev) seen = ev.data end,
    })
    local previous_buf = vim.api.nvim_get_current_buf()
    local ok, err = pcall(results.display, { '| n |', '| - |', '| 1 |' }, sqlite, query, {
      execution_time = 12.5, row_count = 1, connection_name = 'Local SQLite',
      db_type = 'sqlite', timestamp = '12:00:00',
    })
    vim.api.nvim_del_autocmd(id)
    package.loaded['enhance.explorer'], vim.schedule, vim.notify = old_explorer, old_schedule, old_notify
    vim.api.nvim_set_current_buf(previous_buf)

    assert.is_true(ok, err)
    assert.same({
      bufnr = query, result_bufnr = buf, connection = 'Local SQLite',
      row_count = 1, execution_time = 12.5, is_error = false,
    }, seen)
  end)
end)
