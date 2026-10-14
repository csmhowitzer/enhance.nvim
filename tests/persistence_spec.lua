describe('enhance persistence safety', function()
  local explorer, connections, original_stdpath, original_date, root, tab

  before_each(function()
    root = vim.fn.getcwd() .. '/tests/fixtures/c11_persistence_test'
    assert.equals(0, vim.fn.isdirectory(root))
    vim.fn.mkdir(root, 'p')
    original_stdpath = vim.fn.stdpath
    vim.fn.stdpath = function(key)
      if key == 'data' then return root end
      return original_stdpath(key)
    end
    original_date = os.date
    package.loaded['enhance.explorer'] = nil
    package.loaded['enhance.connections'] = nil
    connections = require('enhance.connections')
    connections.setup({ { name = 'C11Safe', type = 'example' } })
    explorer = require('enhance.explorer')
    vim.cmd('tabnew')
    tab = vim.api.nvim_get_current_tabpage()
  end)

  after_each(function()
    os.date = original_date
    if explorer.is_initialized() then explorer.stop() end
    if vim.api.nvim_tabpage_is_valid(tab) then
      vim.api.nvim_set_current_tabpage(tab)
      vim.cmd('tabclose!')
    end
    vim.fn.stdpath = original_stdpath
    assert.equals(0, vim.fn.delete(root, 'rf'))
  end)

  it('creates distinct new-query files even when the clock stays in one second', function()
    explorer.start()
    explorer._set_active_connection(connections.get_connection('C11Safe'))
    os.date = function() return 'same-second' end
    explorer.new_query()
    local first = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    vim.fn.writefile({ 'SELECT first;' }, first)
    explorer.new_query()
    local second = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    assert.not_equals(first, second)
    assert.same({ 'SELECT first;' }, vim.fn.readfile(first))
  end)

  it('autosaves modified tmp buffer bytes to disk and clears modified only on success', function()
    explorer.start()
    explorer._set_active_connection(connections.get_connection('C11Safe'))
    explorer.new_query()
    local buf = vim.api.nvim_get_current_buf()
    local filepath = vim.api.nvim_buf_get_name(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'SELECT 123;', 'SELECT 456;' })
    explorer._save_all_tmp_buffers()
    assert.same({ 'SELECT 123;', 'SELECT 456;' }, vim.fn.readfile(filepath))
    assert.is_false(vim.bo[buf].modified)
  end)

  it('keeps unsaved edits modified and reports a failed autosave', function()
    explorer.start()
    explorer._set_active_connection(connections.get_connection('C11Safe'))
    explorer.new_query()
    local buf = vim.api.nvim_get_current_buf()
    local filepath = vim.api.nvim_buf_get_name(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'SELECT keep me;' })
    local original_call, original_notify = vim.api.nvim_buf_call, vim.notify
    local warning
    vim.api.nvim_buf_call = function() error('write failed') end
    vim.notify = function(message, level)
      if level == vim.log.levels.WARN then warning = message end
    end
    local saved = explorer._save_all_tmp_buffers()
    vim.api.nvim_buf_call, vim.notify = original_call, original_notify
    assert.equals(0, saved)
    assert.is_true(vim.bo[buf].modified)
    assert.equals(0, vim.fn.filereadable(filepath))
    assert.is_not_nil(warning:find('Failed to auto-save', 1, true))
    vim.bo[buf].modified = false
  end)

  it('does not autosave an unrelated SQL buffer in another tmp directory', function()
    explorer.start()
    local dir = root .. '/other/tmp'
    vim.fn.mkdir(dir, 'p')
    local foreign = dir .. '/foreign.sql'
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, foreign)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'SELECT user edit;' })
    assert.equals(0, explorer._save_all_tmp_buffers())
    assert.equals(0, vim.fn.filereadable(foreign))
    assert.is_true(vim.bo[buf].modified)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('rejects unsafe and duplicate names before they become storage paths', function()
    local config = require('enhance.config')
    for _, name in ipairs({ '../escape', 'one/two', 'one\\two', '.', '..', 'glob*', 'a\nb' }) do
      local valid = config.validate_connection({ name = name, type = 'example' })
      assert.is_false(valid, name)
    end
    local original_notify, notice = vim.notify
    vim.notify = function(message, level) notice = { message, level } end
    local ok = connections.setup({ { name = 'C11Safe', type = 'example' },
      { name = 'c11safe', type = 'example' } })
    vim.notify = original_notify
    assert.is_false(ok)
    assert.equals(vim.log.levels.ERROR, notice[2])
    assert.same({}, connections.get_connections())
    local pins = require('enhance.dashboard_pins')
    local pinned, err = pins.toggle({ name = '../escape' }, 'Artists')
    assert.is_nil(pinned)
    assert.matches('name', err)
    assert.equals(0, vim.fn.isdirectory(root .. '/escape'))
  end)

  it('rejects duplicate names in a connections file without writing into shared storage', function()
    local path = root .. '/connections.json'
    vim.fn.writefile({ vim.json.encode({
      { name = 'Example DB', url = 'sqlite:/example.db' },
      { name = 'Example_DB', url = 'sqlite:/another.db' },
    }) }, path)
    local result, err = require('enhance.config').load_connections(path)
    assert.same({}, result)
    assert.matches('duplicate connection name', err)
  end)
end)
