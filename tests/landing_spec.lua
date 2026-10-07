describe('enhance landing page', function()
  local explorer
  local original_test_connection
  local original_system, original_pin_list, original_pin_toggle
  local original_dashboard_fetches
  local original_table_fetches
  local original_setreg

  before_each(function()
    vim.cmd('tabnew')
    package.loaded['enhance.explorer'] = nil
    explorer = require('enhance.explorer')
    original_test_connection = require('enhance.executor').test_connection
    original_system = vim.fn.system
    local pins = require('enhance.dashboard_pins')
    original_pin_list, original_pin_toggle = pins.list, pins.toggle
    local data = require('enhance.dashboard_data')
    original_dashboard_fetches = { data.fetch_sqlserver_rows, data.fetch_pinned_rows,
      data.fetch_pinned_details, data.fetch_database_size }
    local table_data = require('enhance.table_dashboard_data')
    original_table_fetches = { table_data.fetch_create_script, table_data.fetch_references }
  end)

  after_each(function()
    if original_setreg then vim.fn.setreg = original_setreg; original_setreg = nil end
    require('enhance.executor').test_connection = original_test_connection
    vim.fn.system = original_system
    local pins = require('enhance.dashboard_pins')
    pins.list, pins.toggle = original_pin_list, original_pin_toggle
    local data = require('enhance.dashboard_data')
    data.fetch_sqlserver_rows, data.fetch_pinned_rows, data.fetch_pinned_details, data.fetch_database_size =
      unpack(original_dashboard_fetches)
    local table_data = require('enhance.table_dashboard_data')
    table_data.fetch_create_script, table_data.fetch_references = unpack(original_table_fetches)
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

  it('uses the same lettering for the splash and both dashboard banners', function()
    local win = vim.api.nvim_get_current_win()
    local font = require('enhance.banner_font')
    local landing = require('enhance.landing')
    local function expect_banner(buf, name)
      local expected = font.render(name, vim.api.nvim_win_get_width(win))
      local actual = vim.api.nvim_buf_get_lines(buf, 1, #expected + 1, false)
      local padding = name == 'ENHANCE' and (#actual[1] - #expected[1]) or 2
      for i, line in ipairs(expected) do
        assert.equals(string.rep(' ', padding) .. line, actual[i])
      end
    end
    expect_banner(landing.show_welcome(win), 'ENHANCE')
    expect_banner(landing.show_dashboard(win,
      { name = 'Demo', type = 'sqlite', database = 'demo' }, {}), 'demo')
    expect_banner(landing.show_table_dashboard(win,
      { name = 'Demo', type = 'sqlserver' }, 'dbo.Artists', {}, function() end, function() end),
      'dbo.Artists')
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
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:find('dbo.Artists', 1, true) then
        assert.is_not_nil(lines[i + 1]:find('│  ', 1, true))
        assert.is_nil(lines[i + 1]:find('dbo.Albums', 1, true))
        assert.is_not_nil(lines[i + 2]:find('dbo.Albums', 1, true))
      end
    end
  end)

  it('adds a database-wide data card to the overview with loading and unavailable states', function()
    local win = vim.api.nvim_get_current_win()
    local landing = require('enhance.landing')
    local conn = { name = 'Demo', type = 'sqlserver', database = 'demo' }
    local function overview(size)
      local buf = landing.show_dashboard(win, conn, {}, 0, {}, nil, nil, nil, nil, size)
      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      return text:match('(.-)DATABASE OBJECTS')
    end
    assert.is_not_nil(overview(nil):find('DATABASE DATA SIZE', 1, true))
    assert.is_not_nil(overview(nil):find('Loading…', 1, true))
    assert.is_not_nil(overview(1536):find('1.5 MB', 1, true))
    assert.is_not_nil(overview(false):find('Unavailable', 1, true))
    local sqlite = landing.show_dashboard(win, { name = 'Local', type = 'sqlite' }, {}, nil)
    local text = table.concat(vim.api.nvim_buf_get_lines(sqlite, 0, -1, false), '\n')
    assert.is_nil(text:find('DATABASE DATA SIZE', 1, true))
  end)

  it('styles database card borders, headings, labels, and descriptions', function()
    local win = vim.api.nvim_get_current_win()
    local buf = require('enhance.landing').show_dashboard(win,
      { name = 'Demo', type = 'sqlserver', database = 'demo' }, { 'Artists' }, 2,
      { { name = 'dbo.Artists', count = 2500 } }, nil, { 'Artists' },
      { { name = 'dbo.Artists', count = 2500 } },
      { { name = 'dbo.Artists', columns = 3, indexes = 2, data_kb = 1536 } }, 2048)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local marks = vim.api.nvim_buf_get_extmarks(buf,
      vim.api.nvim_create_namespace('enhance_landing'), 0, -1, { details = true })
    local function colored(token, group)
      for row, line in ipairs(lines) do
        local col = line:find(token, 1, true)
        if col then
          for _, mark in ipairs(marks) do
            if mark[2] == row - 1 and mark[3] == col - 1 and mark[4].hl_group == group then
              return true
            end
          end
        end
      end
      return false
    end
    for _, heading in ipairs({ 'DATABASE METADATA', 'DATABASE OBJECTS', 'ROWS PER TABLE', 'PINNED METADATA' }) do
      assert.is_true(colored(heading, 'EnhanceDashboardCategory'))
    end
    for _, label in ipairs({ 'TABLES', 'DATABASE DATA SIZE', 'CONNECTION', 'Database:',
      'ESTIMATED ROWS', 'COLUMNS' }) do
      assert.is_true(colored(label, 'EnhanceDashboardLabel'))
    end
    for _, description in ipairs({ 'Top tables by', 'Estimated rows',
      'SQL Server catalog' }) do
      assert.is_true(colored(description, 'EnhanceDashboardMetaDescription'))
    end
    assert.is_true(colored('╭', 'EnhanceDashboardBorder'))
    require('enhance').setup_highlights()
    assert.equals(0xcba6f7, vim.api.nvim_get_hl(0, { name = 'EnhanceDashboardBorder' }).fg)
  end)

  it('displays pinned SQL Server estimates alphabetically, independent of top eight', function()
    local buf = require('enhance.landing').show_dashboard(vim.api.nvim_get_current_win(),
      { name = 'Demo', type = 'sqlserver', database = 'demo' }, {}, 0, {}, nil,
      { 'dbo.Archive', 'Artists' },
      { { name = 'dbo.Artists', count = 2500 }, { name = 'dbo.Archive', count = 0 } })
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    assert.is_not_nil(text:find('PINNED TABLES  ·  2/8', 1, true))
    assert.is_not_nil(text:find('2,500', 1, true))
    assert.is_not_nil(text:find('0', 1, true))
    assert.is_true(text:find('Artists', 1, true) < text:find('dbo.Archive', 1, true))
  end)

  it('draws spaced bars for alphabetical pins, independent of top-eight ranking', function()
    local win = vim.api.nvim_get_current_win()
    local buf = require('enhance.landing').show_dashboard(win,
      { name = 'Demo', type = 'sqlserver', database = 'demo' }, {}, 0,
      { { name = 'dbo.Top', count = 10000 } }, nil,
      { 'Small', 'Large', 'Missing' },
      { { name = 'dbo.Small', count = 25 }, { name = 'dbo.Large', count = 100 } })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local small_line, large_line, missing_line
    for i, line in ipairs(lines) do
      if line:find('PINNED METADATA', 1, true) then break end
      if line:find('Small', 1, true) then small_line = i end
      if line:find('Large', 1, true) then large_line = i end
      if line:find('Missing', 1, true) then missing_line = i end
    end
    assert.is_true(large_line < missing_line and missing_line < small_line)
    assert.equals(2, missing_line - large_line)
    assert.equals(2, small_line - missing_line)
    local chart_width = math.floor((vim.api.nvim_win_get_width(win) - 6) / 2)
    local function pinned_side(line)
      return vim.fn.strcharpart(line, chart_width + 4)
    end
    local small = pinned_side(lines[small_line])
    local large = pinned_side(lines[large_line])
    local missing = pinned_side(lines[missing_line])
    assert.is_not_nil(small:find('█', 1, true))
    assert.is_not_nil(large:find('█', 1, true))
    assert.is_true(select(2, large:gsub('█', '')) > select(2, small:gsub('█', '')))
    assert.is_nil(missing:find('█', 1, true))
    assert.is_not_nil(missing:find('N/A', 1, true))
    assert.is_true(vim.fn.strdisplaywidth(lines[large_line]) <= vim.api.nvim_win_get_width(win))
  end)

  it('shows three per-category cards for pins with sorted values and sized data', function()
    local win = vim.api.nvim_get_current_win()
    local buf = require('enhance.landing').show_dashboard(win,
      { name = 'Demo', type = 'sqlserver', database = 'demo' }, {}, 0, {}, nil,
      { 'Zoo', 'Artists', 'Missing' }, {}, {
        { name = 'dbo.Zoo', columns = 3, indexes = 0, data_kb = 0 },
        { name = 'dbo.Artists', columns = 12, indexes = 2, data_kb = 1536 },
      })
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    assert.is_not_nil(text:find('PINNED METADATA', 1, true))
    for _, title in ipairs({ 'COLUMNS', 'INDEXES', 'DATA SIZE' }) do
      assert.is_not_nil(text:find('│  ' .. title, 1, true))
    end
    assert.is_not_nil(text:find('1.5 MB', 1, true))
    assert.is_not_nil(text:find('0 kB', 1, true))
    assert.is_not_nil(text:find('N/A', 1, true))
    local columns = text:match('│  COLUMNS.-╯')
    assert.is_true(columns:find('Artists', 1, true) < columns:find('Missing', 1, true))
    assert.is_true(columns:find('Missing', 1, true) < columns:find('Zoo', 1, true))
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= vim.api.nvim_win_get_width(win))
    end
  end)

  it('hides category cards when there are no pinned tables', function()
    local buf = require('enhance.landing').show_dashboard(vim.api.nvim_get_current_win(),
      { name = 'Demo', type = 'sqlserver', database = 'demo' }, {}, 0, {})
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    assert.is_nil(text:find('PINNED METADATA', 1, true))
    assert.is_nil(text:find('│  DATA SIZE', 1, true))
  end)

  it('refreshes visible metadata cards when the batched lookup completes', function()
    local conn = { name = 'Metadata dashboard', type = 'sqlserver', server = 'local', database = 'demo' }
    local data = require('enhance.dashboard_data')
    local top_callback, rows_callback, details_callback, size_callback
    data.fetch_sqlserver_rows = function(_, callback) top_callback = callback end
    data.fetch_pinned_rows = function(_, _, callback) rows_callback = callback end
    data.fetch_pinned_details = function(_, _, callback) details_callback = callback end
    data.fetch_database_size = function(_, callback) size_callback = callback end
    require('enhance.dashboard_pins').list = function() return { 'Artists' } end
    vim.fn.system = function() return 'Artists\n' end
    require('enhance.connections').setup({ conn })
    explorer.start()
    require('enhance.connections').set_current(conn)

    local function dashboard_text()
      return table.concat(vim.api.nvim_buf_get_lines(explorer.get_current_editor_buffer(), 0, -1, false), '\n')
    end
    assert.is_not_nil(dashboard_text():find('Loading catalog metadata', 1, true))
    assert.is_not_nil(dashboard_text():find('DATABASE DATA SIZE', 1, true))
    size_callback(2048)
    assert.is_not_nil(dashboard_text():find('DATABASE DATA SIZE', 1, true))
    assert.is_not_nil(dashboard_text():find('2.0 MB', 1, true))
    details_callback({ { name = 'dbo.Artists', columns = 12, indexes = 2, data_kb = 2048 } })
    assert.is_not_nil(dashboard_text():find('2.0 MB', 1, true))
    top_callback({ { name = 'dbo.Artists', count = 200 } })
    rows_callback({ { name = 'dbo.Artists', count = 200 } })
    assert.is_not_nil(dashboard_text():find('PINNED METADATA', 1, true))
    assert.is_not_nil(dashboard_text():find('█', 1, true))
  end)

  it('places top-eight and pinned cards side by side, stacking only when narrow', function()
    local landing = require('enhance.landing')
    local win = vim.api.nvim_get_current_win()
    local conn = { name = 'Demo', type = 'sqlserver', database = 'demo' }
    local rows = { { name = 'dbo.Artists', count = 2500 }, { name = 'dbo.Albums', count = 120 } }
    local buf = landing.show_dashboard(win, conn, {}, 0, rows, nil, { 'Artists' }, rows)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local shared_line
    for _, line in ipairs(lines) do
      if line:find('ESTIMATED ROWS', 1, true) then shared_line = line end
    end
    assert.is_not_nil(shared_line)
    assert.is_not_nil(shared_line:find('PINNED TABLES', 1, true))
    for _, line in ipairs(lines) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= vim.api.nvim_win_get_width(win))
    end

    vim.cmd('vsplit')
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(win, 55)
    buf = landing.show_dashboard(win, conn, {}, 0, rows, nil, { 'Artists' }, rows)
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local chart_line, pinned_line
    for i, line in ipairs(lines) do
      if line:find('ESTIMATED ROWS', 1, true) then chart_line = i end
      if line:find('PINNED TABLES', 1, true) then pinned_line = i end
      assert.is_true(vim.fn.strdisplaywidth(line) <= vim.api.nvim_win_get_width(win))
    end
    assert.is_true(chart_line < pinned_line)
  end)

  it('uses the configurable border highlight on card corners and sides', function()
    local enhance = require('enhance')
    local saved = enhance.config
    enhance.config = { ui = { dashboard = { card_border = 'EnhanceTestBorder' } } }
    local buf = require('enhance.landing').show_dashboard(vim.api.nvim_get_current_win(),
      { name = 'Demo', type = 'sqlite', database = 'demo' }, {})
    enhance.config = saved
    local ns = vim.api.nvim_create_namespace('enhance_landing')
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local found = 0
    for _, mark in ipairs(marks) do
      if mark[4].hl_group == 'EnhanceTestBorder' then found = found + 1 end
    end
    assert.is_true(found > 4)
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

  it('pins and unpins explorer tables from the keymap or expanded table action', function()
    local conn = { name = 'Pin menu test', type = 'sqlite', path = 'test.db' }
    require('enhance.connections').setup({ conn })
    require('enhance.executor').test_connection = function() return true end
    vim.fn.system = function() return 'Artists\nAlbums\n' end
    local pins = require('enhance.dashboard_pins')
    local names = {}
    pins.list = function() return vim.deepcopy(names) end
    pins.toggle = function(_, name)
      if names[1] == name then names = {}; return false end
      names = { name }; return true
    end

    explorer.start()
    explorer._handle_enter(3)
    local function line_with(needle)
      for i, line in ipairs(explorer._build_explorer_content()) do
        if line:find(needle, 1, true) then return i end
      end
    end
    explorer._handle_enter(line_with('Tables (2)'))
    local table_line = line_with('󰓫  Artists')
    local explorer_buf = vim.api.nvim_get_current_buf()
    explorer.open()
    explorer_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_cursor(0, { table_line, 0 })
    local maps = vim.api.nvim_buf_get_keymap(explorer_buf, 'n')
    local pin_map
    for _, map in ipairs(maps) do
      if map.lhs:lower():find('dp', 1, true) then pin_map = map.callback; break end
    end
    assert.is_function(pin_map)
    pin_map()
    assert.same({ 'Artists' }, names)
    local lines = explorer._build_explorer_content()
    assert.is_not_nil(lines[table_line]:find('Artists 󰐃', 1, true))
    assert.equals('Artists', explorer._parse_line(lines[table_line], table_line).table_name)
    explorer._handle_enter(table_line)
    local action_line = line_with('Unpin from dashboard')
    assert.equals('table_pin', explorer._parse_line(explorer._build_explorer_content()[action_line], action_line).type)
    explorer._handle_enter(action_line)
    assert.same({}, names)
    assert.is_not_nil(explorer._build_explorer_content()[table_line]:find('Artists', 1, true))
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

  it('renders a responsive table dashboard with a full schema and selectable references', function()
    local win = vim.api.nvim_get_current_win()
    local chosen
    local ref = { kind = 'View', name = 'dbo.ArtistView' }
    local saved = { kind = 'Saved Query', name = 'artists.sql', path = '/queries/artists.sql' }
    local script = "-- Catalog preview\nCREATE TABLE [dbo].[Artists] (\n    [Id] int NOT NULL,\n    [Name] nvarchar(120) DEFAULT N'guest',\n    PRIMARY KEY ([Id])\n);"
    local buf = require('enhance.landing').show_table_dashboard(win,
      { name = 'Demo', type = 'sqlserver' }, 'dbo.Artists', {
        rows = { count = 2500 }, metrics = { indexes = 2, columns = 3, data_kb = 1536 },
        script = script,
        references = { ref },
        saved = { saved },
      }, function(selected) chosen = selected end, function() end)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, '\n')
    for _, label in ipairs({ 'TABLE METADATA', 'ROW COUNT', 'INDEXES', 'COLUMNS', 'TABLE SIZE', 'CREATE TABLE',
      'PRIMARY KEY ([Id])', '2,500', '1.5 MB', 'dbo.ArtistView', 'artists.sql' }) do
      assert.is_not_nil(text:find(label, 1, true))
    end
    assert.is_not_nil(text:find('yc copy', 1, true))
    assert.is_not_nil(text:find('<CR> to select', 1, true))
    assert.is_nil(text:find('╭─ REFERENCES', 1, true))
    assert.is_nil(text:find('b   Back', 1, true))
    assert.is_true(text:find('TABLE METADATA', 1, true) < text:find('ROW COUNT', 1, true))
    assert.is_not_nil(text:find('󰒉  dbo.ArtistView', 1, true))
    assert.is_not_nil(text:find('  artists.sql', 1, true))
    assert.is_nil(text:find('SAVED QUERIES', 1, true))
    assert.is_nil(text:find('↳', 1, true))
    local ns = vim.api.nvim_create_namespace('enhance_landing')
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local function has_highlight(token, group)
      for row, line in ipairs(lines) do
        if line:find('│  ', 1, true) then
          local col = line:find(token, 1, true)
          if col then
            for _, mark in ipairs(marks) do
              if mark[2] == row - 1 and mark[3] == col - 1 and mark[4].hl_group == group then
                return true
              end
            end
          end
        end
      end
      return false
    end
    assert.is_true(has_highlight('CREATE', 'Statement'))
    assert.is_true(has_highlight('[dbo]', 'Identifier'))
    assert.is_true(has_highlight('nvarchar', 'Type'))
    assert.is_true(has_highlight('120', 'Number'))
    assert.is_true(has_highlight("'guest'", 'String'))
    assert.is_true(has_highlight('-- Catalog preview', 'Comment'))
    assert.is_true(has_highlight('ROW COUNT', 'EnhanceDashboardLabel'))
    assert.is_true(has_highlight('Catalog estimate', 'EnhanceDashboardMetaDescription'))
    assert.is_true(has_highlight('Non-heap indexes', 'EnhanceDashboardMetaDescription'))
    assert.is_true(has_highlight('SQL SERVER', 'EnhanceDashboardLabel'))
    local function mark_for(token, group)
      for row, line in ipairs(lines) do
        local col = line:find(token, 1, true)
        if col then
          for _, mark in ipairs(marks) do
            if mark[2] == row - 1 and mark[3] == col - 1 and mark[4].hl_group == group then
              return true
            end
          end
        end
      end
      return false
    end
    assert.is_true(mark_for('TABLE METADATA', 'EnhanceDashboardCategory'))
    assert.is_true(mark_for('CREATE TABLE', 'EnhanceDashboardCategory'))
    assert.is_true(mark_for('REFERENCES', 'EnhanceDashboardCategory'))
    assert.is_true(mark_for('╭', 'EnhanceDashboardTableBorder'))
    assert.is_true(mark_for('<CR> to select', 'EnhanceDashboardHint'))
    assert.is_true(mark_for('yc copy', 'EnhanceDashboardHint'))
    require('enhance').setup_highlights()
    assert.is_true(vim.api.nvim_get_hl(0, { name = 'EnhanceDashboardHint' }).italic)
    local description_hl = vim.api.nvim_get_hl(0, { name = 'EnhanceDashboardMetaDescription' })
    assert.is_true(description_hl.italic)
    assert.equals(vim.api.nvim_get_hl(0, { name = 'Comment' }).fg or 0x6c7086, description_hl.fg)
    local reference_border, script_border
    for i, line in ipairs(lines) do
      if line:match('^  REFERENCES$') then reference_border = lines[i + 1]; break end
      if line:match('^  CREATE TABLE$') then script_border = lines[i + 1] end
    end
    assert.is_not_nil(reference_border)
    assert.is_not_nil(script_border)
    for _, pair in ipairs({ { reference_border, '<CR> to select' }, { script_border, 'yc copy' } }) do
      local left, right = pair[1]:match('╭(.-) ' .. pair[2] .. ' (.-)╮')
      assert.is_not_nil(left)
      assert.is_true(math.abs(vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right)) <= 1)
    end
    local saved_line, view_line
    for i, line in ipairs(lines) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= vim.api.nvim_win_get_width(win))
      if line:find('  artists.sql', 1, true) then saved_line = i end
      if line:find('󰒉  dbo.ArtistView', 1, true) then view_line = i end
    end
    assert.equals(saved_line + 1, view_line)
    local selection_ns = vim.api.nvim_create_namespace('enhance_landing_reference_selection')
    local function selected_row()
      local selection = vim.api.nvim_buf_get_extmarks(buf, selection_ns, 0, -1, { details = true })
      assert.is_true(#selection <= 1)
      return selection[1] and selection[1][2] + 1
    end
    assert.is_nil(selected_row())
    vim.api.nvim_win_set_cursor(win, { saved_line, 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
    assert.equals(saved_line, selected_row())
    local selection = vim.api.nvim_buf_get_extmarks(buf, selection_ns, 0, -1, { details = true })[1]
    assert.equals('EnhanceDashboardReferenceSelected', selection[4].hl_group)
    assert.equals(lines[saved_line]:find('  artists.sql', 1, true) - 1, selection[3])
    assert.equals(selection[3] + #'  artists.sql', selection[4].end_col)
    local maps = vim.api.nvim_buf_get_keymap(buf, 'n')
    local select_ref, copy_script
    for _, map in ipairs(maps) do
      if map.lhs == '<CR>' then select_ref = map.callback end
      if map.lhs == 'yc' then copy_script = map.callback end
      assert.not_equals('b', map.lhs)
    end
    assert.is_function(copy_script)
    local copied
    original_setreg = vim.fn.setreg
    vim.fn.setreg = function(register, value)
      assert.equals('+', register)
      copied = value
    end
    copy_script()
    assert.equals(script, copied)
    vim.fn.setreg = original_setreg
    original_setreg = nil
    select_ref()
    assert.same(saved, chosen)
    vim.cmd('normal! j')
    assert.equals(view_line, vim.api.nvim_win_get_cursor(win)[1])
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
    assert.equals(view_line, selected_row())
    select_ref()
    assert.same(ref, chosen)
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
    assert.is_nil(selected_row())
  end)

  it('keeps copy and reference hints inside narrow table cards', function()
    vim.cmd('vsplit')
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(win, 28)
    local buf = require('enhance.landing').show_table_dashboard(win,
      { name = 'Demo', type = 'sqlserver' }, 'Artists', {
        script = 'CREATE TABLE [dbo].[Artists] ([Id] int);', references = {},
      }, function() end, function() end)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, '\n')
    assert.is_not_nil(text:find('SQL SERVER', 1, true))
    assert.is_not_nil(text:find('yc copy', 1, true))
    assert.is_not_nil(text:find('<CR> to select', 1, true))
    for _, line in ipairs(lines) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= vim.api.nvim_win_get_width(win))
    end
  end)

  it('offers a Dashboard action under every SQL Server table', function()
    local conn = { name = 'Table dashboard menu', type = 'sqlserver', server = 'local', database = 'demo' }
    require('enhance.connections').setup({ conn })
    vim.fn.system = function() return 'Artists\nAlbums\n' end
    local data = require('enhance.dashboard_data')
    data.fetch_sqlserver_rows = function() end
    data.fetch_database_size = function() end
    require('enhance.executor').test_connection = function() return true end
    explorer.start()
    explorer._handle_enter(3)
    local function line_with(needle)
      for i, line in ipairs(explorer._build_explorer_content()) do
        if line:find(needle, 1, true) then return i end
      end
    end
    explorer._handle_enter(line_with('Tables (2)'))
    for _, name in ipairs({ 'Artists', 'Albums' }) do
      explorer._handle_enter(line_with('󰓫  ' .. name))
    end
    local dashboards = 0
    for i, line in ipairs(explorer._build_explorer_content()) do
      if line:find('Dashboard', 1, true) then
        local info = explorer._parse_line(line, i)
        if info and info.type == 'table_dashboard' then dashboards = dashboards + 1 end
      end
    end
    assert.equals(2, dashboards)
    data.fetch_pinned_rows = function(_, _, cb) cb({ { name = 'dbo.Artists', count = 42 } }) end
    data.fetch_pinned_details = function(_, _, cb)
      cb({ { name = 'dbo.Artists', indexes = 1, columns = 2, data_kb = 512 } })
    end
    local table_data = require('enhance.table_dashboard_data')
    table_data.fetch_create_script = function(_, _, cb) cb('CREATE TABLE [dbo].[Artists] ([Id] int);') end
    table_data.fetch_references = function(_, _, cb) cb({ { kind = 'View', name = 'dbo.ArtistView' } }) end
    local menu_line
    for i, line in ipairs(explorer._build_explorer_content()) do
      if line:find('          ', 1, true) and line:find('Dashboard', 1, true) then
        menu_line = i; break
      end
    end
    explorer._handle_enter(menu_line)
    local buf = explorer.get_current_editor_buffer()
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    assert.is_not_nil(text:find('TABLE DASHBOARD', 1, true))
    assert.is_not_nil(text:find('dbo.ArtistView', 1, true))
    assert.is_not_nil(text:find('42', 1, true))
    local query = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), query)
    assert.is_true(vim.api.nvim_buf_is_valid(buf))
    explorer._handle_enter(menu_line)
    assert.equals(buf, explorer.get_current_editor_buffer())
    explorer.open_table_dashboard(conn, 'Albums')
    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), query)
    explorer.open_table_dashboard(conn, 'Artists')
    assert.not_equals(buf, explorer.get_current_editor_buffer())
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
    local callbacks = {}
    data.fetch_pinned_rows = function(_, _, cb) callbacks[#callbacks + 1] = cb end
    explorer.open_table_dashboard(conn, 'Albums', true)
    local hidden = explorer.get_current_editor_buffer()
    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), query)
    callbacks[1]({ { name = 'dbo.Albums', count = 99 } })
    explorer.open_table_dashboard(conn, 'Albums')
    assert.not_equals(hidden, explorer.get_current_editor_buffer())
    assert.equals(2, #callbacks)
    callbacks[2]({ { name = 'dbo.Albums', count = 99 } })
    assert.is_not_nil(table.concat(vim.api.nvim_buf_get_lines(
      explorer.get_current_editor_buffer(), 0, -1, false), '\n'):find('99', 1, true))
  end)
end)
