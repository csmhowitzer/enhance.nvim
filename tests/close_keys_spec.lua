-- q closes the explorer and the results window, as the footer and README say
describe('q closes', function()
  local function has_q(buf, desc)
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      if map.lhs == 'q' then return map.desc == desc end
    end
    return false
  end

  it('the results window, and only that window', function()
    local results = require('enhance.results')
    local buf = vim.api.nvim_create_buf(false, true)
    results.setup_keymaps(buf)
    assert.is_true(has_q(buf, 'Close results'))
    vim.cmd('split')
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    local before = #vim.api.nvim_tabpage_list_wins(0)
    vim.api.nvim_feedkeys('q', 'x', false)
    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.equals(before - 1, #vim.api.nvim_tabpage_list_wins(0))
    -- the last window is never closed
    vim.api.nvim_win_set_buf(0, buf)
    vim.cmd('only')
    vim.api.nvim_feedkeys('q', 'x', false)
    assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))
  end)

  it('the explorer', function()
    local explorer = require('enhance.explorer')
    local old_notify = vim.notify
    vim.notify = function() end
    assert.is_true(pcall(explorer.start))
    vim.notify = old_notify
    assert.is_true(explorer.is_open())
    local win = vim.tbl_filter(function(w)
      return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'enhance-explorer'
    end, vim.api.nvim_tabpage_list_wins(0))[1]
    assert.is_truthy(win, 'explorer window found')
    assert.is_true(has_q(vim.api.nvim_win_get_buf(win), 'Close explorer'))
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_feedkeys('q', 'x', false)
    assert.is_false(explorer.is_open())
    pcall(explorer.stop)
  end)
end)
