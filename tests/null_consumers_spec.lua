describe('explicit SQL NULL result consumers', function()
  local function parsed()
    return { headers = { 'missing', 'empty', 'literal' }, rows = { { vim.NIL, '', 'NULL' } },
      column_types = { 'nvarchar', 'nvarchar', 'nvarchar' }, metadata = { transport = 'helper' } }
  end

  it('renders explicit NULL differently from empty text and preserves original row values', function()
    local lines, map = require('enhance.formatter').format(parsed(), { null_display = '<missing>' })
    assert.is_truthy(lines[3]:find('<missing>', 1, true))
    local cells = vim.split(lines[3], '|', { plain = true })
    assert.equals('', vim.trim(cells[3]))
    assert.equals('NULL', vim.trim(cells[4]))
    assert.are.same(parsed().rows[1], map[3].values)
    assert.is_true(map[3].explicit_nulls)
  end)

  it('samples around actual NULLs but does not mistake literal NULL text for absent JSON', function()
    local detector = require('enhance.json_detector')
    assert.is_true(detector.detect_json_columns({ 'json' }, { { vim.NIL }, { '{"ok":true}' } }, nil, true)[1])
    assert.is_false(detector.detect_json_columns({ 'json' }, { { 'NULL' }, { '{"ok":true}' } }, nil, true)[1])
  end)

  it('preserves NULL semantics across multiple result sets and statement formatting', function()
    local formatter = require('enhance.formatter')
    local _, map = formatter.format({ multiple_results = true, result_sets = { parsed(), parsed() } })
    local count = 0
    for _, row in pairs(map) do
      count = count + 1
      assert.is_true(row.explicit_nulls)
      assert.equals(vim.NIL, row.values[1])
    end
    assert.equals(2, count)
    local _, _, statement_map = formatter.format_multiple_statements({ { result_table = parsed(), rows = 1 } })
    assert.is_true(statement_map[3].explicit_nulls)
  end)

  local buf, previous, registers, wins
  before_each(function()
    previous = vim.api.nvim_get_current_buf()
    registers = { vim.fn.getreg('"'), vim.fn.getreg('+') }
    wins = vim.api.nvim_list_wins()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'enhance-results'
    local lines, map = require('enhance.formatter').format(parsed())
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    require('enhance.result_state').set(buf, 'enhance_result_rows', map)
    require('enhance.result_state').set(buf, 'enhance_result_sections', { { header_line = 1, headers = parsed().headers, rows = parsed().rows, row_lines = { 3 } } })
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
  end)
  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not vim.tbl_contains(wins, win) then vim.api.nvim_win_close(win, true) end
    end
    vim.api.nvim_set_current_buf(previous)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.setreg('"', registers[1]); vim.fn.setreg('+', registers[2])
  end)

  it('copies actual NULLs rather than Lua userdata, keeping empty field positions', function()
    local results = require('enhance.results')
    results.copy_cell()
    assert.equals('NULL', vim.fn.getreg('"'))
    results.copy_row()
    assert.equals('NULL\t\tNULL', vim.fn.getreg('"'))
    results.copy_result_set()
    assert.equals('#\tmissing\tempty\tliteral\n1\tNULL\t\tNULL', vim.fn.getreg('"'))
  end)

  it('opens actual NULL in a NULL-colored popup, not a userdata string', function()
    require('enhance.results').show_cell()
    assert.are.same({ '', '  NULL  ', '' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    assert.is_truthy(vim.wo.winhighlight:find('FloatBorder:EnhanceNull', 1, true))
  end)

  it('does not give literal NULL text a NULL-colored popup', function()
    local row = require('enhance.result_state').get(buf, 'enhance_result_rows')[3]
    vim.api.nvim_win_set_cursor(0, { 3, row.widths[1] + row.widths[2] + 8 })
    require('enhance.results').show_cell()
    assert.are.same({ '', '  NULL  ', '' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    assert.is_nil(vim.wo.winhighlight:find('FloatBorder:EnhanceNull', 1, true))
  end)

  it('shows an empty-string cell as empty, not NULL', function()
    local row = require('enhance.result_state').get(buf, 'enhance_result_rows')[3]
    vim.api.nvim_win_set_cursor(0, { 3, row.widths[1] + 5 })
    require('enhance.results').show_cell()
    assert.are.same({ '', '    ', '' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('highlights actual NULL only, not literal NULL text or empty text', function()
    local results = require('enhance.results')
    results.apply_null_highlighting(buf, {})
    local marks = vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace('enhance_null_highlight'), 0, -1, { details = true })
    assert.equals(1, #marks)
    assert.equals(2, marks[1][2])
    assert.equals(2, marks[1][3])
    results.apply_type_highlighting(buf, {}, { result_rows = require('enhance.result_state').get(buf, 'enhance_result_rows') })
    local types = vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace('enhance_type_highlight'), 0, -1, { details = true })
    for _, mark in ipairs(types) do assert.not_equals(2, mark[3]) end
  end)
end)
