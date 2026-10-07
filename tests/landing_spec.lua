describe('enhance landing page', function()
  local explorer
  local original_test_connection

  before_each(function()
    vim.cmd('tabnew')
    package.loaded['enhance.explorer'] = nil
    explorer = require('enhance.explorer')
    original_test_connection = require('enhance.executor').test_connection
  end)

  after_each(function()
    require('enhance.executor').test_connection = original_test_connection
    if explorer.is_initialized() then
      explorer.stop()
    else
      vim.cmd('tabclose!')
    end
  end)

  it('replaces the welcome buffer with a dashboard after connecting', function()
    vim.wo.list = true
    explorer.start()
    local welcome = explorer.get_current_editor_buffer()
    assert.is_true(require('enhance.landing').is_landing(welcome))
    assert.is_false(vim.bo[welcome].buflisted)
    assert.is_false(vim.wo.list)
    assert.matches('Select a database', table.concat(vim.api.nvim_buf_get_lines(welcome, 0, -1, false), '\n'))

    -- The same successful-connection path used by the explorer and connection browser.
    require('enhance.connections').set_current({ name = 'Demo', type = 'example', database = 'demo' })
    local dashboard = explorer.get_current_editor_buffer()
    assert.not_equals(welcome, dashboard)
    assert.is_false(vim.api.nvim_buf_is_valid(welcome))
    local text = table.concat(vim.api.nvim_buf_get_lines(dashboard, 0, -1, false), '\n')
    assert.is_not_nil(text:find('Demo  |  DASHBOARD', 1, true))
    assert.is_not_nil(text:find('0 tables', 1, true))
    assert.is_not_nil(text:find('Not available', 1, true))
    assert.is_true(text:find('n   New query', 1, true) < text:find('DATABASE OBJECTS', 1, true))

    explorer.refresh_dashboard({ name = 'Demo', type = 'example', database = 'demo' })
    local refreshed = explorer.get_current_editor_buffer()
    assert.not_equals(dashboard, refreshed)
    assert.is_false(vim.api.nvim_buf_is_valid(dashboard))

    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), vim.api.nvim_create_buf(true, false))
    assert.is_true(vim.wait(200, function() return vim.wo.list end, 10))
  end)

  it('leaves an existing file alone when opening the workspace', function()
    local original = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(original, 'enhance-landing-existing.sql')
    vim.api.nvim_buf_set_lines(original, 0, -1, false, { 'SELECT 1;' })

    explorer.start()
    assert.equals(original, explorer.get_current_editor_buffer())
    assert.same({ 'SELECT 1;' }, vim.api.nvim_buf_get_lines(original, 0, -1, false))
  end)

  it('opens its welcome page over a Neovim startup dashboard', function()
    local startup = vim.api.nvim_get_current_buf()
    vim.bo[startup].buftype = 'nofile'
    vim.bo[startup].filetype = 'snacks_dashboard'
    vim.api.nvim_buf_set_lines(startup, 0, -1, false, { 'Start Neovim' })

    explorer.start()
    assert.is_true(require('enhance.landing').is_landing(explorer.get_current_editor_buffer()))
  end)

  it('shows real object counts and table names in responsive panels', function()
    vim.cmd('vsplit')
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(win, 45)
    local buf = require('enhance.landing').show_dashboard(win,
      { name = 'Demo', type = 'sqlite', database = 'sample.db' }, { 'Artists', 'Albums' }, 2)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, '\n')
    assert.is_not_nil(text:find('2 tables', 1, true))
    assert.is_not_nil(text:find('2 views', 1, true))
    assert.is_not_nil(text:find('Artists', 1, true))
    assert.is_not_nil(text:find('sample.db', 1, true))
    local expected = require('enhance.banner_font').render('sample.db', vim.api.nvim_win_get_width(win))
    local actual = vim.api.nvim_buf_get_lines(buf, 1, #expected + 1, false)
    for i, line in ipairs(actual) do
      assert.equals('  ' .. expected[i], line)
    end
    for _, line in ipairs(lines) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= vim.api.nvim_win_get_width(win))
    end
  end)

  it('shows bounded SQL Server row estimates as labeled bars', function()
    local win = vim.api.nvim_get_current_win()
    local buf = require('enhance.landing').show_dashboard(win,
      { name = 'Demo', type = 'sqlserver', database = 'demo' }, { 'Artists' }, 0,
      { { name = 'dbo.Artists', count = 2500 }, { name = 'dbo.Albums', count = 0 } })
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    assert.is_not_nil(text:find('ROWS PER TABLE', 1, true))
    assert.is_not_nil(text:find('dbo.Artists', 1, true))
    assert.is_not_nil(text:find('2,500', 1, true))
    assert.is_not_nil(text:find('█', 1, true))
  end)

  it('shows saved queries and only persisted temp buffers as separate counts', function()
    local win = vim.api.nvim_get_current_win()
    local buf = require('enhance.landing').show_dashboard(win,
      { name = 'Demo', type = 'example', database = 'demo' }, {}, nil, nil,
      { saved_queries = 7, temp_buffers = 3 })
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    assert.is_not_nil(text:find('SAVED QUERIES', 1, true))
    assert.is_not_nil(text:find('7 saved', 1, true))
    assert.is_not_nil(text:find('TEMP BUFFERS', 1, true))
    assert.is_not_nil(text:find('3 on disk', 1, true))
  end)

  it('keeps the dashboard available from its explorer entry after opening a query', function()
    local conn = { name = 'Menu Demo', type = 'example', database = 'demo' }
    require('enhance.connections').setup({ conn })
    require('enhance.executor').test_connection = function() return true end
    explorer.start()
    explorer._handle_enter(3)

    local dashboard = explorer.get_current_editor_buffer()
    local query = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), query)
    assert.is_true(vim.api.nvim_buf_is_valid(dashboard))

    local menu_line
    for i, line in ipairs(explorer._build_explorer_content()) do
      if line:find('Dashboard', 1, true) then menu_line = i; break end
    end
    assert.is_not_nil(menu_line)
    explorer._handle_enter(menu_line)
    assert.equals(dashboard, explorer.get_current_editor_buffer())
    assert.is_true(vim.api.nvim_buf_is_valid(query))
  end)

  it('keeps every card border aligned with its content', function()
    local panel = require('enhance.landing')._panel
    for _, width in ipairs({ 24, 42, 80 }) do
      local lines = panel('TABLES', { '39 tables', 'Long value that may be clipped' }, width)
      for _, line in ipairs(lines) do
        assert.equals(width, vim.fn.strdisplaywidth(line))
      end
    end
  end)
end)
