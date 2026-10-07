-- Tests for enhance.nvim results module

describe("enhance.results", function()
  local results
  
  before_each(function()
    -- Reset module state before each test
    package.loaded["enhance.results"] = nil
    results = require("enhance.results")
  end)
  
  describe("setup_keymaps", function()
    it("should set up keymaps for results buffer", function()
      -- Create a test buffer
      local buf = vim.api.nvim_create_buf(false, true)
      
      -- Setup keymaps
      results._setup_keymaps(buf)
      
      -- Verify buffer is valid
      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      
      -- Get buffer keymaps
      local keymaps = vim.api.nvim_buf_get_keymap(buf, 'n')

      -- Copy mappings must remain buffer-local, alongside the existing refresh map.
      local found = {}
      for _, map in ipairs(keymaps) do
        found[map.lhs] = true
      end

      assert.is_true(found.r)
      assert.is_true(found.yc)
      assert.is_true(found.yr)
      for _, lhs in ipairs({ 'ys', 'gk', '<M-k>', '<M-j>', '<M-h>', '<M-l>' }) do
        assert.is_true(found[lhs], lhs .. ' must be buffer-local')
      end
      assert.is_nil(found.K, 'K is reserved for window navigation')
      assert.is_nil(found.gK, 'gK was replaced by gk')
      assert.is_nil(found['<M-p>'], 'Alt-p belongs to tmux')
      for _, lhs in ipairs({ 'h', 'j', 'k', 'l' }) do
        assert.is_nil(found[lhs], lhs .. ' must retain its native movement')
      end
      for _, lhs in ipairs({ '[s', ']s', '[r', ']r', '[c', ']c' }) do
        assert.is_nil(found[lhs], lhs .. ' was replaced')
      end
      
      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
    
    it("should set keymaps only for specific buffer", function()
      local buf1 = vim.api.nvim_create_buf(false, true)
      local buf2 = vim.api.nvim_create_buf(false, true)
      
      -- Setup keymaps only for buf1
      results._setup_keymaps(buf1)
      
      -- Get keymaps for both buffers
      local keymaps1 = vim.api.nvim_buf_get_keymap(buf1, 'n')
      local keymaps2 = vim.api.nvim_buf_get_keymap(buf2, 'n')

      -- buf1 should have 'r' keymap
      local buf1_has_r = false
      for _, map in ipairs(keymaps1) do
        if map.lhs == 'r' then
          buf1_has_r = true
        end
      end
      assert.is_true(buf1_has_r)

      -- buf2 should not have 'r' keymap
      local buf2_has_r = false
      for _, map in ipairs(keymaps2) do
        if map.lhs == 'r' then
          buf2_has_r = true
        end
      end
      assert.is_false(buf2_has_r)
      
      -- Cleanup
      vim.api.nvim_buf_delete(buf1, { force = true })
      vim.api.nvim_buf_delete(buf2, { force = true })
    end)
  end)

  describe("copying original result values", function()
    local previous_buf, previous_register, previous_clipboard, previous_plus
    local buf

    local function popup_title(win)
      local title = vim.api.nvim_win_get_config(win).title
      return type(title) == 'table' and title[1][1] or title
    end

    before_each(function()
      previous_buf = vim.api.nvim_get_current_buf()
      previous_register = vim.fn.getreg('"')
      previous_plus = vim.fn.getreg('+')
      previous_clipboard = vim.o.clipboard
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.bo[buf].filetype = 'enhance-results'
    end)

    after_each(function()
      vim.api.nvim_win_set_buf(0, previous_buf)
      vim.api.nvim_buf_delete(buf, { force = true })
      vim.o.clipboard = previous_clipboard
      vim.fn.setreg('+', previous_plus)
      vim.fn.setreg('"', previous_register)
    end)

    it("copies the full cell and tab-separated row instead of the shortened display", function()
      local formatter = require('enhance.formatter')
      local full = string.rep('x', 80)
      local lines, row_map = formatter.format({ headers = { 'ID', 'Value' }, rows = { { '1', full } } })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
      vim.api.nvim_win_set_cursor(0, { 3, 8 })

      assert.is_truthy(lines[3]:find('...', 1, true))
      results.copy_cell()
      assert.equals(full, vim.fn.getreg('"'))
      results.copy_row()
      assert.equals('1\t' .. full, vim.fn.getreg('"'))
    end)

    it("shows the original truncated value with its SQL type color in a popup", function()
      local full = string.rep('1234567890', 12)
      local lines, row_map = require('enhance.formatter').format({
        headers = { 'Amount' }, rows = { { full } }, column_types = { 'decimal(12,3)' },
      })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
      vim.api.nvim_win_set_cursor(0, { 3, 2 })
      assert.is_truthy(lines[3]:find('...', 1, true))

      results.show_cell()
      local popup = vim.api.nvim_get_current_win()
      local popup_buf = vim.api.nvim_get_current_buf()
      assert.not_equals(buf, popup_buf)
      assert.not_equals('', vim.api.nvim_win_get_config(popup).relative)
      assert.equals(' Amount (decimal(12,3)) ', popup_title(popup))
      assert.is_truthy(vim.wo[popup].winhighlight:find('FloatBorder:EnhanceNumberCell', 1, true))
      assert.are.same({ '', '  ' .. full .. '  ', '' },
        vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false))
      local ns = vim.api.nvim_create_namespace('enhance_cell_hover')
      local marks = vim.api.nvim_buf_get_extmarks(popup_buf, ns, 0, -1, { details = true })
      assert.equals('EnhanceNumberCell', marks[1][4].hl_group)
      assert.are.same({ 1, 2 }, { marks[1][2], marks[1][3] })
      local maps = vim.api.nvim_buf_get_keymap(popup_buf, 'n')
      local close = {}
      for _, map in ipairs(maps) do close[map.lhs] = true end
      assert.is_true(close.q)
      assert.is_true(close['<Esc>'])
      vim.api.nvim_win_close(popup, true)
    end)

    it("opens the same popup for an ordinary untruncated cell", function()
      local lines, row_map = require('enhance.formatter').format({
        headers = { 'Name' }, rows = { { 'Ada' } },
      })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
      vim.api.nvim_win_set_cursor(0, { 3, 2 })
      results.setup_keymaps(buf)

      local popup_map
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
        if map.lhs == 'gk' then popup_map = map end
      end
      assert.is_not_nil(popup_map)
      popup_map.callback()

      local popup = vim.api.nvim_get_current_win()
      assert.not_equals(buf, vim.api.nvim_get_current_buf())
      assert.equals(' Name ', popup_title(popup))
      assert.equals('NormalFloat:Normal', vim.wo[popup].winhighlight)
      assert.are.same({ '', '  Ada  ', '' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
      vim.api.nvim_win_close(popup, true)
    end)

    it('pads a one-character cell on all four sides', function()
      local lines, row_map = require('enhance.formatter').format({
        headers = { 'Flag' }, rows = { { '1' } }, column_types = { 'int' },
      })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
      vim.api.nvim_win_set_cursor(0, { 3, 2 })
      results.show_cell()
      assert.are.same({ '', '  1  ', '' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
      assert.is_true(vim.api.nvim_win_get_width(0) >= 5)
      vim.api.nvim_win_close(0, true)
    end)

    it("opens detected JSON in the JSON viewer with its column name and SQL type", function()
      local full = '{"description":"' .. string.rep('x', 90) .. '","ok":true}'
      local lines, row_map = require('enhance.formatter').format({
        headers = { 'metadata' }, rows = { { full } }, column_types = { 'nvarchar(max)' },
      })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
      vim.api.nvim_win_set_cursor(0, { 3, 2 })

      results.show_cell()
      local popup = vim.api.nvim_get_current_win()
      local popup_buf = vim.api.nvim_get_current_buf()
      assert.equals(' JSON View - metadata (nvarchar(max)) (Row 1/1) ', popup_title(popup))
      assert.equals('json', vim.bo[popup_buf].filetype)
      local content = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
      assert.is_true(#content > 1)
      assert.is_truthy(table.concat(content, '\n'):find(string.rep('x', 90), 1, true))
      require('enhance.json_viewer').close()
    end)

    it("colors the border for date and NULL cells using their result highlights", function()
      local lines, row_map = require('enhance.formatter').format({
        headers = { 'StartedAt', 'Optional' }, rows = { { '2026-01-17', 'NULL' } },
        column_types = { 'date', 'nvarchar(20)' },
      })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
      vim.api.nvim_win_set_cursor(0, { 3, 2 })

      results.show_cell()
      local popup = vim.api.nvim_get_current_win()
      assert.equals(' StartedAt (date) ', popup_title(popup))
      assert.is_truthy(vim.wo[popup].winhighlight:find('FloatBorder:EnhanceDateCell', 1, true))
      vim.api.nvim_win_close(popup, true)

      vim.api.nvim_win_set_cursor(0, { 3, row_map[3].widths[1] + 5 })
      results.show_cell()
      popup = vim.api.nvim_get_current_win()
      assert.equals(' Optional (nvarchar(20)) ', popup_title(popup))
      assert.is_truthy(vim.wo[popup].winhighlight:find('FloatBorder:EnhanceNull', 1, true))
      vim.api.nvim_win_close(popup, true)
    end)

    it("pastes a copied cell with unnamedplus and exposes it to the system clipboard", function()
      vim.o.clipboard = 'unnamedplus'
      local full = string.rep('json', 75)
      local formatter = require('enhance.formatter')
      local lines, row_map = formatter.format({ headers = { 'ID', 'Value' }, rows = { { '1', full } } })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
      vim.api.nvim_win_set_cursor(0, { 3, 8 })

      results.copy_cell()
      assert.equals(full, vim.fn.getreg('+'))

      local paste_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, paste_buf)
      vim.cmd('normal! p')
      assert.equals(full, vim.api.nvim_buf_get_lines(paste_buf, 0, 1, false)[1])
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_delete(paste_buf, { force = true })
    end)

    it("maps mixed statements to the correct row and ignores non-data lines", function()
      local formatter = require('enhance.formatter')
      local lines, _, row_map = formatter.format_multiple_statements({
        { message = '✓ Updated 1 row', rows = 1 },
        { result_table = { headers = { 'ID', 'Data' }, rows = { { '2', 'a|b' } } }, rows = 1 },
      })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
      local data_line
      for line_num in pairs(row_map) do data_line = line_num end

      vim.api.nvim_win_set_cursor(0, { data_line, 8 })
      results.copy_cell()
      assert.equals('a|b', vim.fn.getreg('"'))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      results.copy_row()
      assert.equals('a|b', vim.fn.getreg('"'))
    end)

    it("moves between result sets and columns without entering another table", function()
      local statements = {
        { result_table = { headers = { 'ID', 'JSON' }, rows = { { '1', '{"a":"x|y"}' }, { '2', 'short' } } }, rows = 2 },
        { result_table = { headers = { 'Empty' }, rows = {} }, rows = 0 },
        { message = '✓ Updated 1 row', rows = 1 },
        { result_table = { headers = { 'Name' }, rows = { { 'last' } } }, rows = 1 },
      }
      local formatter = require('enhance.formatter')
      local lines, _, row_map = formatter.format_multiple_statements(statements)
      local sections = results._build_result_sections(lines, row_map, {
        statement_results = statements,
        parsed_result = { multiple_results = true, result_sets = {
          { headers = { 'Wrong' }, rows = {} }, { headers = { 'Wrong' }, rows = {} },
          { headers = { 'Wrong' }, rows = {} },
        } },
      }, 0)
      assert.is_nil(sections[3].headers)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_sections', sections)

      vim.api.nvim_win_set_cursor(0, { sections[1].row_lines[1], 2 })
      results.navigate('column', 1)
      assert.equals(8, vim.api.nvim_win_get_cursor(0)[2])
      results.copy_cell()
      assert.equals('{"a":"x|y"}', vim.fn.getreg('"'))
      results.navigate('column', 1)
      assert.are.same({ sections[1].row_lines[1], 2 }, vim.api.nvim_win_get_cursor(0))
      results.navigate('column', -1)
      assert.are.same({ sections[1].row_lines[1], 8 }, vim.api.nvim_win_get_cursor(0))
      vim.api.nvim_win_set_cursor(0, { sections[1].row_lines[2], 8 })
      results.navigate('column', -1)
      assert.equals(2, vim.api.nvim_win_get_cursor(0)[2])

      results.navigate('set', 1)
      assert.equals(sections[2].header_line, vim.api.nvim_win_get_cursor(0)[1])
      results.navigate('set', 1)
      assert.equals(sections[3].header_line, vim.api.nvim_win_get_cursor(0)[1])
      results.navigate('set', 1)
      assert.are.same({ sections[4].row_lines[1], 2 }, vim.api.nvim_win_get_cursor(0))
      results.navigate('set', 1)
      assert.are.same({ sections[1].row_lines[1], 2 }, vim.api.nvim_win_get_cursor(0))
      results.navigate('set', -1)
      assert.are.same({ sections[4].row_lines[1], 2 }, vim.api.nvim_win_get_cursor(0))
      results.navigate('set', -1)
      assert.equals(sections[3].header_line, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it("copies one complete table with row numbers, headers and untruncated cells", function()
      local json = '{"data":"' .. string.rep('x', 80) .. '"}'
      local statements = {
        { result_table = { headers = { 'ID', 'metadata' }, rows = { { '1', json }, { '2', 'a\tb' } } }, rows = 2 },
        { result_table = { headers = { 'Other' }, rows = { { 'different' } } }, rows = 1 },
      }
      local lines, _, row_map = require('enhance.formatter').format_multiple_statements(statements)
      local sections = results._build_result_sections(lines, row_map, { statement_results = statements }, 0)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_sections', sections)
      vim.api.nvim_win_set_cursor(0, { sections[1].row_lines[1], 2 })
      results.copy_result_set()
      assert.equals('#\tID\tmetadata\n1\t1\t' .. json .. '\n2\t2\t"a\tb"', vim.fn.getreg('"'))

      vim.api.nvim_win_set_cursor(0, { sections[2].header_line, 0 })
      results.copy_result_set()
      assert.equals('#\tOther\n1\tdifferent', vim.fn.getreg('"'))
    end)

    it("retains headers for an empty table and offsets sections below the status line", function()
      local table_result = { headers = { 'Empty' }, rows = {} }
      local lines, row_map = require('enhance.formatter').format(table_result)
      local displayed = { 'Rows: 0', '-----', unpack(lines) }
      local sections = results._build_result_sections(displayed, row_map, { parsed_result = table_result }, 2)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, displayed)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_sections', sections)
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      results.copy_result_set()
      assert.equals('#\tEmpty', vim.fn.getreg('"'))
    end)

    it("enters the first result row from the status line with right", function()
      local lines, row_map = require('enhance.formatter').format({
        headers = { 'ID', 'Name' }, rows = { { '1', 'Ada' } },
      })
      local displayed = { 'Rows: 1', '-----', unpack(lines) }
      local shifted = {}
      for line, row in pairs(row_map) do shifted[line + 2] = row end
      local sections = results._build_result_sections(displayed, shifted, nil, 2)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, displayed)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', shifted)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_sections', sections)

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      results.navigate('column', 1)
      assert.are.same({ sections[1].row_lines[1], 2 }, vim.api.nvim_win_get_cursor(0))
    end)

    it('toggles aligned, color-matched datatype rows without changing result lines or copies', function()
      local formatter = require('enhance.formatter')
      local statements = {
        { result_table = {
          headers = { 'ID', 'Name', 'Started' }, rows = { { '1', 'Ada', '2026-01-17' } },
          column_types = { 'int', 'nvarchar(255)', 'date' },
        }, rows = 1 },
        { result_table = {
          headers = { 'Empty' }, rows = {}, column_types = { 'decimal(10,2)' },
        }, rows = 0 },
      }
      local lines, _, row_map = formatter.format_multiple_statements(statements)
      local sections = results._build_result_sections(lines, row_map, { statement_results = statements }, 0)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_rows', row_map)
      vim.api.nvim_buf_set_var(buf, 'enhance_result_sections', sections)
      local ns = vim.api.nvim_create_namespace('enhance_datatype_headers')

      results.toggle_datatypes()
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
      assert.equals(2, #marks)
      local chunks = marks[1][4].virt_lines[1]
      assert.equals('int', vim.trim(chunks[2][1]))
      assert.equals('EnhanceNumberCell', chunks[2][2])
      assert.equals('nvarchar(255)', vim.trim(chunks[4][1]))
      assert.equals('Normal', chunks[4][2])
      assert.equals('date', vim.trim(chunks[6][1]))
      assert.equals('EnhanceDateCell', chunks[6][2])
      assert.equals('decimal(10,2)', vim.trim(marks[2][4].virt_lines[1][2][1]))
      assert.are.same(lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      vim.api.nvim_win_set_cursor(0, { sections[1].row_lines[1], 2 })
      results.copy_result_set()
      assert.equals('#\tID\tName\tStarted\n1\t1\tAda\t2026-01-17', vim.fn.getreg('"'))

      results.toggle_datatypes()
      assert.equals(0, #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
    end)

    it("highlights the JSON cell at its rendered width after truncation", function()
      local formatter = require('enhance.formatter')
      local json = '{"key":"' .. string.rep('a|b', 30) .. '"}'
      local lines, _, row_map = formatter.format_multiple_statements({
        { message = '✓ Updated 1 row' },
        { result_table = { headers = { 'ID', 'JSON' }, rows = { { '1', json } } }, rows = 1 },
      })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      results.apply_json_highlighting(buf, {}, nil, { result_rows = row_map })
      local ns = vim.api.nvim_create_namespace('enhance_json_highlight')
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
      assert.equals(1, #marks)
      local line_num
      for n in pairs(row_map) do line_num = n end
      assert.equals(line_num - 1, marks[1][2])
      assert.equals(8, marks[1][3])
      assert.equals(58, marks[1][4].end_col)
    end)

    it("highlights only JSON cells when other rows are SQL NULL", function()
      local formatter = require('enhance.formatter')
      local lines, row_map = formatter.format({
        headers = { 'metadata' },
        rows = { { '{"version":"2.1"}' }, { 'NULL' }, { '{"version":"1.5"}' } },
      })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      results.apply_json_highlighting(buf, {}, nil, { result_rows = row_map })
      local ns = vim.api.nvim_create_namespace('enhance_json_highlight')
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.equals(2, #marks)
      assert.equals(2, marks[1][2])
      assert.equals(4, marks[2][2])
    end)

    it("colors SQL Server typed cells across result sets but leaves text, NULL and JSON alone", function()
      local formatter = require('enhance.formatter')
      local statements = {
        { result_table = {
          headers = { 'ID', 'StartedAt', 'TextDate', 'NumericText', 'JSON', 'Amount' },
          rows = {
            { '1', '2026-01-17 12:00:00.123', 'Jan 17 2026', '123', '{"a":1}', 'NULL' },
            { 'NULL', 'NULL', '2026-01-18', '456', '{"a":2}', '12.50' },
          },
          column_types = { 'int', 'datetime2(3)', 'nvarchar(255)', 'varchar(20)', 'nvarchar(max)', 'decimal(10,2)' },
        }, rows = 2 },
        { result_table = {
          headers = { 'Moment' }, rows = { { '12:34:56' } }, column_types = { 'time(7)' },
        }, rows = 1 },
      }
      local lines, _, row_map = formatter.format_multiple_statements(statements)
      local displayed = { 'Rows: 3', '-----', unpack(lines) }
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, displayed)
      results.apply_type_highlighting(buf, { status_line = { enabled = true, position = 'top' } }, {
        result_rows = row_map,
      })
      local ns = vim.api.nvim_create_namespace('enhance_type_highlight')
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
      assert.equals(4, #marks)
      local colored = {}
      for _, mark in ipairs(marks) do
        colored[mark[2] .. ':' .. mark[3]] = mark[4].hl_group
      end
      for line_num, row in pairs(row_map) do
        local displayed_line = line_num + 1 -- 2-line status offset, 0-based extmarks
        local expected = #row.headers == 1 and { [1] = 'EnhanceDateCell' }
          or { [1] = 'EnhanceNumberCell', [2] = 'EnhanceDateCell', [6] = 'EnhanceNumberCell' }
        for col, group in pairs(expected) do
          if row.column_types[col] and row.values[col] ~= 'NULL' then
            local start = 2
            for i = 1, col - 1 do start = start + row.widths[i] + 3 end
            assert.equals(group, colored[displayed_line .. ':' .. start])
          end
        end
      end
      -- Reusing a result buffer must clear its old type colors.
      results.apply_type_highlighting(buf, {}, { result_rows = {} })
      assert.equals(0, #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
    end)
  end)
  
  describe("display_message", function()
    it("should create a buffer with message content", function()
      local test_lines = {
        "Error: Connection failed",
        "Please check your database configuration"
      }
      
      -- Mock explorer module to avoid dependencies
      package.loaded["enhance.explorer"] = {
        get_results_window = function() return nil end,
        set_results_window = function() end,
      }
      
      -- Display message
      results.display_message(test_lines)
      
      -- Find the message buffer
      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local name = vim.api.nvim_buf_get_name(buf)
          if name:match("%[Enhance%] Message") then
            found_buf = buf
            break
          end
        end
      end
      
      assert.is_not_nil(found_buf, "Should create message buffer")
      
      -- Verify buffer properties
      assert.equals('enhance-results', vim.bo[found_buf].filetype)
      assert.is_false(vim.bo[found_buf].modifiable)
      
      -- Verify content
      local lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      assert.equals(2, #lines)
      assert.equals("Error: Connection failed", lines[1])
      assert.equals("Please check your database configuration", lines[2])
      
      -- Cleanup
      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)
    
    it("should apply error highlighting when is_error is true", function()
      local test_lines = {
        "Query Execution Failed",
        "",
        "Msg 208, Level 16, State 1",
        "Invalid object name 'blech'."
      }

      -- Mock explorer module
      package.loaded["enhance.explorer"] = {
        get_results_window = function() return nil end,
        set_results_window = function() end,
      }

      -- Mock enhance module for config
      package.loaded["enhance"] = {
        get_config = function()
          return {
            status_line = {
              enabled = false
            }
          }
        end,
        setup_highlights = function() end,
      }

      -- Display error message with is_error flag
      results.display_message(test_lines, true)

      -- Find the message buffer
      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local name = vim.api.nvim_buf_get_name(buf)
          if name:match("%[Enhance%] Message") then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf, "Should create message buffer")

      -- Verify content
      local lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      assert.equals(4, #lines)
      assert.equals("Query Execution Failed", lines[1])

      -- Note: We can't easily verify highlight application in tests
      -- but we verify the function was called without errors

      -- Cleanup
      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should set buffer as non-modifiable", function()
      local test_lines = { "Test message" }
      
      -- Mock explorer module
      package.loaded["enhance.explorer"] = {
        get_results_window = function() return nil end,
        set_results_window = function() end,
      }
      
      results.display_message(test_lines)
      
      -- Find the message buffer
      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local name = vim.api.nvim_buf_get_name(buf)
          if name:match("%[Enhance%] Message") then
            found_buf = buf
            break
          end
        end
      end
      
      assert.is_not_nil(found_buf)
      assert.is_false(vim.bo[found_buf].modifiable)
      
      -- Cleanup
      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)
  end)

  describe("DDL/DML success messages", function()
    local enhance

    before_each(function()
      -- Mock enhance module with config
      package.loaded["enhance"] = {
        get_config = function()
          return {
            format_results = true,
            status_line = {
              enabled = true,
              position = "top",
              highlights = {
                label = "EnhanceStatusLabel",
                value = "EnhanceStatusValue",
                connection = "EnhanceStatusConnection",
                db_type = "EnhanceStatusDBType",
                timestamp = "EnhanceStatusTimestamp",
                separator = "EnhanceStatusSeparator",
                line_number = "EnhanceLineNumber",
                line_number_accent = "EnhanceLineNumberAccent",
              },
            },
            ui = {
              results_position = "split",
              show_query_time = true,
            },
          }
        end,
        setup_highlights = function() end,
      }

      -- Mock explorer module
      package.loaded["enhance.explorer"] = {
        get_results_window = function() return nil end,
        set_results_window = function() end,
      }

      -- Reload results module
      package.loaded["enhance.results"] = nil
      results = require("enhance.results")
    end)

    it("should add success message for CREATE TABLE", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "CREATE_TABLE",
        row_count = 0,
        execution_time = 0.05,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      -- Find the results buffer
      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf, "Should create results buffer")

      -- Get buffer content
      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)

      -- Check for success message
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Table created successfully") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain CREATE TABLE success message")

      -- Cleanup
      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should add success message for DROP TABLE", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "DROP_TABLE",
        row_count = 0,
        execution_time = 0.03,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Table dropped successfully") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain DROP TABLE success message")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should add success message for ALTER TABLE", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "ALTER_TABLE",
        row_count = 0,
        execution_time = 0.04,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Table altered successfully") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain ALTER TABLE success message")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should add success message for INSERT with row count", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "INSERT",
        row_count = 3,
        execution_time = 0.02,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Inserted 3 rows") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain INSERT success message with row count")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should add success message for INSERT with singular row", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "INSERT",
        row_count = 1,
        execution_time = 0.01,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        -- Should be "row" not "rows" for singular
        if line:match("✓ Inserted 1 row") and not line:match("rows") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain INSERT success message with singular 'row'")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should add success message for UPDATE with row count", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "UPDATE",
        row_count = 5,
        execution_time = 0.03,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Updated 5 rows") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain UPDATE success message with row count")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should add success message for DELETE with row count", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "DELETE",
        row_count = 2,
        execution_time = 0.02,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Deleted 2 rows") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain DELETE success message with row count")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should not add message when there are result rows", function()
      local lines = { "ProductID  Name", "1          Laptop" }
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "INSERT",
        row_count = 1,
        execution_time = 0.01,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Inserted") then
          has_message = true
          break
        end
      end

      -- Should NOT add message when there are result rows
      assert.is_false(has_message, "Should not add message when result rows exist")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)
  end)
end)
