-- Delete and rename only ever touch Enhance's own query files (tmp or saved), never other files on disk.
describe('query file safety', function()
  local explorer = require('enhance.explorer')
  local root = vim.fn.stdpath('data') .. '/enhance.nvim'

  it('recognises only tmp and saved query files inside Enhance storage', function()
    assert.is_true(explorer._is_query_file(root .. '/Dev/tmp/1030121530-000003-new-query.sql'))
    assert.is_true(explorer._is_query_file(root .. '/Dev/queries/report.sql'))
    assert.is_false(explorer._is_query_file('/home/user/project/src/Program.cs'))
    assert.is_false(explorer._is_query_file('/home/user/project/schema.sql'))
    assert.is_false(explorer._is_query_file(root .. '/Dev/queries/../../../../etc/passwd.sql'))
    assert.is_false(explorer._is_query_file(root .. '/Dev/other/x.sql'))
    assert.is_false(explorer._is_query_file(root .. '/Dev/queries/sub/x.sql'))
    assert.is_false(explorer._is_query_file(root .. '/Dev/queries/notes.txt'))
    assert.is_false(explorer._is_query_file(''))
  end)

  it('<leader>od refuses a project file and deletes nothing', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    local file = dir .. '/keep.sql'
    vim.fn.writefile({ 'SELECT 1;' }, file)
    vim.cmd('edit ' .. vim.fn.fnameescape(file))
    local old_confirm, old_notify, asked = vim.fn.confirm, vim.notify, false
    vim.fn.confirm = function() asked = true; return 1 end
    vim.notify = function() end
    require('enhance').confirm_delete_file()
    vim.fn.confirm, vim.notify = old_confirm, old_notify
    assert.is_false(asked, 'no prompt for a file that will not be deleted')
    assert.equals(1, vim.fn.filereadable(file))
    vim.cmd('bwipeout!')
    vim.fn.delete(dir, 'rf')
  end)
end)
