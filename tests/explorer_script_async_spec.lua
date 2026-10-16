describe('explorer metadata script responsiveness', function()
  local explorer, cli, connections, root, tab, old_stdpath, old_async, old_sync, old_notify
  local pending, stopped, notifications

  before_each(function()
    root = vim.fn.getcwd() .. '/tests/fixtures/c08_script_test'
    assert.equals(0, vim.fn.isdirectory(root))
    vim.fn.mkdir(root, 'p')
    old_stdpath = vim.fn.stdpath
    vim.fn.stdpath = function(key)
      if key == 'data' then return root end
      return old_stdpath(key)
    end
    package.loaded['enhance.explorer'] = nil
    package.loaded['enhance.connections'] = nil
    connections = require('enhance.connections')
    explorer = require('enhance.explorer')
    cli = require('enhance.db.cli_credentials')
    old_async, old_sync = cli.system_async, cli.system
    old_notify = vim.notify
    notifications = {}
    vim.notify = function(message, level) notifications[#notifications + 1] = { message, level } end
    pending, stopped = {}, 0
    cli.system = function() error('script menu must not call synchronous CLI') end
    cli.system_async = function(cmd, _, _, callback)
      pending[#pending + 1] = { cmd = cmd, callback = callback }
      return { kill = function() stopped = stopped + 1 end }
    end
    vim.cmd('tabnew')
    tab = vim.api.nvim_get_current_tabpage()
  end)

  after_each(function()
    cli.system_async, cli.system = old_async, old_sync
    if explorer.is_initialized() then explorer.stop() end
    if vim.api.nvim_tabpage_is_valid(tab) then
      vim.api.nvim_set_current_tabpage(tab)
      vim.cmd('tabclose!')
    end
    vim.fn.stdpath = old_stdpath
    vim.notify = old_notify
    assert.equals(0, vim.fn.delete(root, 'rf'))
  end)

  local function choose_action(conn, section, icon, object, action)
    connections.setup({ conn })
    explorer.start()
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = { 'Database Explorer', '', '✗ ▾ 󰆼 ' .. conn.name,
      '    ▾ ' .. icon .. '  ' .. section .. ' (1)',
      '      ▾ ' .. icon .. '  ' .. object,
      '          󰓫  ' .. action }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    explorer._set_explorer_buf(buf)
    local info = explorer._parse_line(lines[6], 6)
    assert.is_not_nil(info)
    explorer._handle_open(6)
    return buf
  end

  it('opens a CREATE template only after its CLI finishes, without blocking the editor', function()
    local conn = { name = 'C08 SQLite', type = 'sqlite', path = 'test.db' }
    local buf = choose_action(conn, 'Tables', '󰓱', 'Artists', 'CREATE Table')
    assert.equals(1, #pending)
    assert.equals('sqlite3', pending[1].cmd[1])
    assert.equals(0, vim.fn.isdirectory(root .. '/enhance.nvim/' .. conn.name .. '/tmp'))
    pending[1].callback('CREATE TABLE Artists (id integer);', 0)
    local path = vim.api.nvim_buf_get_name(explorer.get_current_editor_buffer())
    assert.matches('/enhance.nvim/C08 SQLite/tmp/', path, 1, true)
    assert.same({ 'CREATE TABLE Artists (id integer);' }, vim.fn.readfile(path))
    explorer._set_explorer_buf(nil)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('opens a generated UPDATE template and reports a failed lookup without synchronous fallback', function()
    local conn = { name = 'C08 MySQL', type = 'mysql', host = 'local', database = 'demo' }
    local buf = choose_action(conn, 'Tables', '󰓱', '`Artists`', 'UPDATE Template')
    assert.equals(1, #pending)
    assert.equals(0, vim.fn.isdirectory(root .. '/enhance.nvim/' .. conn.name .. '/tmp'))
    pending[1].callback(nil, 1)
    local path = vim.api.nvim_buf_get_name(explorer.get_current_editor_buffer())
    assert.same({ '-- Failed to generate table_update script for `Artists`' }, vim.fn.readfile(path))
    local reported = false
    for _, event in ipairs(notifications) do
      if event[2] == vim.log.levels.ERROR and event[1]:find('Failed to generate', 1, true) then
        reported = true
      end
    end
    assert.is_true(reported)
    explorer._set_explorer_buf(nil)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  for _, kind in ipairs({ 'Views', 'Stored Procedures', 'Functions' }) do
    it('loads and transforms a ' .. kind .. ' ALTER definition asynchronously', function()
      local conn = { name = 'C08 SQL Server', type = 'sqlserver', server = 'local', database = 'demo' }
      local icon = ({ Views = '󰒉', ['Stored Procedures'] = '󰊢', Functions = '󰡱' })[kind]
      local label = ({ Views = 'View', ['Stored Procedures'] = 'Procedure', Functions = 'Function' })[kind]
      local buf = choose_action(conn, kind, icon, '[dbo].[Artists]', 'ALTER ' .. label)
      assert.equals(1, #pending)
      pending[1].callback('CREATE ' .. label:upper() .. ' [dbo].[Artists] AS SELECT 1;', 0)
      local path = vim.api.nvim_buf_get_name(explorer.get_current_editor_buffer())
      assert.same({ 'ALTER ' .. label:upper() .. ' [dbo].[Artists] AS SELECT 1;' }, vim.fn.readfile(path))
      explorer._set_explorer_buf(nil)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end

  it('ignores and stops a late ALTER definition after the workspace closes', function()
    local conn = { name = 'C08 SQL Server', type = 'sqlserver', server = 'local', database = 'demo' }
    local buf = choose_action(conn, 'Views', '󰒉', '[dbo].[Artists]', 'ALTER View')
    assert.equals(1, #pending)
    explorer._set_explorer_buf(nil)
    explorer.stop()
    assert.equals(1, stopped)
    local visible = vim.api.nvim_get_current_buf()
    pending[1].callback('CREATE VIEW [dbo].[Artists] AS SELECT 1;', 0)
    assert.equals(visible, vim.api.nvim_get_current_buf())
    assert.equals(0, vim.fn.isdirectory(root .. '/enhance.nvim/' .. conn.name .. '/tmp'))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('does not open a completed script for a connection that was switched away', function()
    local conn = { name = 'C08 Switch', type = 'sqlite', path = 'test.db' }
    local buf = choose_action(conn, 'Tables', '󰓱', 'Artists', 'CREATE Table')
    assert.equals(1, #pending)
    local old_show_dashboard = explorer.show_dashboard
    explorer.show_dashboard = function() end
    connections.set_current({ name = 'Other', type = 'example' })
    explorer.show_dashboard = old_show_dashboard
    pending[1].callback('CREATE TABLE Artists (id integer);', 0)
    assert.equals(0, vim.fn.isdirectory(root .. '/enhance.nvim/' .. conn.name .. '/tmp'))
    explorer._set_explorer_buf(nil)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
