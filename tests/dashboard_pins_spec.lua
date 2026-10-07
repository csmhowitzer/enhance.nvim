describe('enhance dashboard pins', function()
  local pins = require('enhance.dashboard_pins')
  local original = {}
  local files

  before_each(function()
    files = {}
    for _, fn in ipairs({ 'filereadable', 'readfile', 'writefile', 'mkdir', 'isdirectory' }) do
      original[fn] = vim.fn[fn]
    end
    vim.fn.filereadable = function(path) return files[path] and 1 or 0 end
    vim.fn.readfile = function(path) return files[path] end
    vim.fn.writefile = function(lines, path) files[path] = lines; return 0 end
    vim.fn.mkdir = function() return 1 end
  end)

  after_each(function()
    for fn, value in pairs(original) do vim.fn[fn] = value end
  end)

  it('persists eight pins per connection in pin order, with no credential data', function()
    local conn = { name = 'Pinned test', type = 'sqlserver', password = 'private' }
    for i = 1, 8 do
      assert.is_true(pins.toggle(conn, 'dbo.Table ' .. i))
    end
    assert.same(8, #pins.list(conn))
    assert.is_true(pins.has(conn, 'dbo.Table 1'))
    local pinned, err = pins.toggle(conn, 'Ninth')
    assert.is_nil(pinned)
    assert.matches('up to 8', err)
    assert.is_false(pins.toggle(conn, 'dbo.Table 2'))
    assert.is_true(pins.toggle(conn, 'New Table'))
    assert.equals('New Table', pins.list(conn)[8])
    assert.same({}, pins.list({ name = 'Another connection' }))
    for _, lines in pairs(files) do
      assert.is_nil(table.concat(lines):find('private', 1, true))
    end
  end)
end)
