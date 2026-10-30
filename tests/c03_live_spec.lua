-- Explicit developer opt-in only. Normal nvt runs never load personal credentials
-- or contact a database. Queries are SELECT-only and create no server objects.
if vim.env.ENHANCE_C03_LIVE ~= '1' then
  describe('C03 live database acceptance', function() pending('opt-in: set ENHANCE_C03_LIVE=1') end)
  return
end

describe('C03 live database acceptance', function()
  local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
  local original_results, original_notify, restore, connections, displayed
  local targets = {
    { name = 'Docker SQL Server', fixture = 'sqlserver', precise = '123456789012345678901234567890.12345678', binary = '0x000AFF' },
    { name = 'Docker MySQL', fixture = 'mysql', precise = '123456789012345678901234567890.123456789', binary = '0x000AFF' },
    { name = 'Docker PostgreSQL', fixture = 'postgres', precise = '123456789012345678901234567890.123456789', binary = '\\x000aff' },
  }

  before_each(function()
    connections = select(1, require('enhance.config').load_connections('~/.local/share/enhance/connections.json'))
    local candidate = vim.env.ENHANCE_TEST_RELEASE_CANDIDATE
    restore = dofile(root .. '/../enhance-helper-dev.lua').enable(
      candidate and candidate .. '/main' or root .. '/dist/helper-v1.1.1',
      candidate and candidate .. '/postgres' or root .. '/dist/postgres-helper-v1.1.1')
    original_results, original_notify = require('enhance.results'), vim.notify
    displayed = nil
    -- Leave the real executor, subprocess, decoder and formatter in place;
    -- capture only the final UI boundary to avoid altering the user's layout.
    package.loaded['enhance.results'] = { display = function(lines, _, _, metadata)
      displayed = { lines = lines, metadata = metadata }
    end }
    vim.notify = function() end
  end)

  after_each(function()
    require('enhance.executor').cancel_query()
    package.loaded['enhance.results'], vim.notify = original_results, original_notify
    if restore then restore(); restore = nil end
  end)

  local function execute(target, sql)
    local connection
    for _, candidate in ipairs(connections) do
      if candidate.name == target.name then connection = candidate; break end
    end
    assert.is_not_nil(connection, 'Required live connection is missing: ' .. target.name)
    require('enhance.executor').execute(connection, sql)
    assert.is_true(vim.wait(55000, function() return displayed ~= nil end, 10), 'Live execution did not complete')
    return displayed.metadata
  end

  local function check_consumers(metadata, line, row, expected)
    local previous = vim.api.nvim_get_current_buf()
    local windows = vim.api.nvim_list_wins()
    local registers = { vim.fn.getreg('"'), vim.fn.getreg('+') }
    local buf = vim.api.nvim_create_buf(false, true)
    local ok, err = pcall(function()
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'enhance-results'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, displayed.lines)
      require('enhance.result_state').set(buf, 'enhance_result_rows', metadata.result_rows)
      vim.api.nvim_win_set_cursor(0, { line, 2 })
      original_results.copy_cell()
      assert.equals(expected[1], vim.fn.getreg('"'))
      original_results.copy_row()
      local copied = vim.deepcopy(expected)
      copied[2] = 'NULL'
      assert.equals(table.concat(copied, '\t'), vim.fn.getreg('"'))
      local long_column = 2
      for i = 1, 4 do long_column = long_column + row.widths[i] + 3 end
      vim.api.nvim_win_set_cursor(0, { line, long_column })
      original_results.copy_cell()
      assert.equals(expected[5], vim.fn.getreg('"'))
      original_results.show_cell()
      assert.are.same({ '', '  ' .. expected[5] .. '  ', '' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not vim.tbl_contains(windows, win) then vim.api.nvim_win_close(win, true) end
    end
    vim.api.nvim_set_current_buf(previous)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.setreg('"', registers[1]); vim.fn.setreg('+', registers[2])
    assert.is_true(ok, err)
  end

  for _, target in ipairs(targets) do
    it('preserves exact fields and result-set identity on ' .. target.name, function()
      local sql = table.concat(vim.fn.readfile(root .. '/tests/fixtures/c03-' .. target.fixture .. '.sql'), '\n')
      local metadata = execute(target, sql)
      assert.is_false(metadata.is_error, 'Live helper returned an error; inspect connection availability')
      assert.equals(2, metadata.row_count)
      local parsed = metadata.parsed_result
      assert.is_true(parsed.multiple_results)
      assert.equals(3, #parsed.result_sets)
      local first, empty, last = unpack(parsed.result_sets)
      assert.are.same({ 'same', 'same', 'empty_value', 'literal_null', 'long_value', 'precise_value', 'binary_value' }, first.headers)
      assert.equals(1, #first.rows)
      local expected = { '  pipe|tab\tline\r\n雪  ', vim.NIL, '', 'NULL', string.rep('x', 10000), target.precise, target.binary }
      assert.are.same(expected, first.rows[1])
      assert.are.same({ 'empty_header' }, empty.headers)
      assert.equals(0, #empty.rows)
      assert.are.same({ 'value' }, last.headers)
      assert.are.same({ { 'second set' } }, last.rows)
      local mapped, data_line = {}, nil
      for line, row in pairs(metadata.result_rows) do
        if #row.values == 7 then mapped[#mapped + 1] = row; data_line = line end
      end
      assert.equals(1, #mapped)
      assert.are.same(expected, mapped[1].values)
      assert.is_true(mapped[1].explicit_nulls)
      assert.are.same(first.headers, mapped[1].headers)
      check_consumers(metadata, data_line, mapped[1], expected)
    end)

    it('retains earlier results and native later errors on ' .. target.name, function()
      local sql = "SELECT 'before error' AS value; SELECT CAST('c03-invalid-integer' AS "
        .. (target.fixture == 'mysql' and 'UNSUPPORTED_C03_TYPE' or 'int') .. ') AS value;'
      -- MySQL validates a later syntax error after executing the first statement.
      local metadata = execute(target, sql)
      assert.is_true(metadata.is_error)
      assert.is_not_nil(metadata.errors)
      assert.is_true(#metadata.errors > 0)
      assert.are.same({ { 'before error' } }, metadata.parsed_result.rows)
      assert.equals(1, metadata.row_count)
      if target.fixture ~= 'sqlserver' then
        assert.is_string(metadata.errors[1].sqlState)
        assert.equals(5, #metadata.errors[1].sqlState)
      end
    end)
  end
end)
