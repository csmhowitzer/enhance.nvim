describe('enhance.json_viewer result rows', function()
  local function popup_title(win)
    local title = vim.api.nvim_win_get_config(win).title
    return type(title) == 'table' and title[1][1] or title
  end

  it('opens the original JSON cell in a mixed result set even when display is truncated', function()
    local previous_buf = vim.api.nvim_get_current_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    local viewer = require('enhance.json_viewer')
    local formatter = require('enhance.formatter')
    local json = '{"value":"' .. string.rep('a|b', 30) .. '"}'
    local lines, _, row_map = formatter.format_multiple_statements({
      { message = '✓ Updated 1 row' },
      { result_table = {
        headers = { 'ID', 'metadata' }, rows = { { '1', json }, { '2', 'NULL' } },
        column_types = { 'int', 'nvarchar(max)' },
      }, rows = 2 },
    })

    vim.api.nvim_win_set_buf(0, buf)
    vim.bo[buf].filetype = 'enhance-results'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
    local data_line
    for line_num, row in pairs(row_map) do
      if row.row_idx == 1 then data_line = line_num end
    end
    vim.api.nvim_win_set_cursor(0, { data_line, 8 })

    local _, value, row_idx, col_idx = viewer._get_current_cell_info()
    assert.equals(json, value)
    assert.equals(1, row_idx)
    assert.equals(2, col_idx)

    viewer.show()
    assert.equals(' JSON View - metadata (nvarchar(max)) (Row 1/2) ', popup_title(0))
    local mappings = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, 'n')) do
      mappings[map.lhs:lower()] = true
    end
    for _, lhs in ipairs({ '<M-j>', '<M-k>', '<M-h>', '<M-l>', '<C-n>', '<C-p>', '<C-h>', '<C-l>' }) do
      assert.is_true(mappings[lhs:lower()], lhs .. ' should work in the JSON viewer')
    end
    local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
    assert.is_truthy(content:find(string.rep('a|b', 30), 1, true))

    viewer.close()
    vim.api.nvim_win_set_buf(0, previous_buf)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('updates the column name and type when navigating JSON rows and columns', function()
    local previous_buf = vim.api.nvim_get_current_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    local viewer = require('enhance.json_viewer')
    local lines, row_map = require('enhance.formatter').format({
      headers = { 'metadata', 'details' },
      rows = {
        { '{"row":1}', '{"other":1}' },
        { '{"row":2}', '{"other":2}' },
      },
      column_types = { 'nvarchar(max)', 'varchar(255)' },
    })
    vim.api.nvim_win_set_buf(0, buf)
    vim.bo[buf].filetype = 'enhance-results'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
    vim.api.nvim_win_set_cursor(0, { 3, 2 })

    viewer.show()
    assert.equals(' JSON View - metadata (nvarchar(max)) (Row 1/2) ', popup_title(0))
    viewer.navigate_next()
    assert.equals(' JSON View - metadata (nvarchar(max)) (Row 2/2) ', popup_title(0))
    viewer.navigate_next_column()
    assert.equals(' JSON View - details (varchar(255)) (Row 2/2) ', popup_title(0))
    viewer.navigate_prev_column()
    assert.equals(' JSON View - metadata (nvarchar(max)) (Row 2/2) ', popup_title(0))

    viewer.close()
    vim.api.nvim_win_set_buf(0, previous_buf)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
