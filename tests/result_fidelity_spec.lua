describe('result field fidelity', function()
  local parser = require('enhance.parser')

  local fixtures = {
    { name = 'MySQL TSV blank middle and trailing fields', db = 'mysql',
      lines = { 'id\tmiddle\tlast', '1\t\t', '2\tvalue\tend' },
      headers = { 'id', 'middle', 'last' }, rows = { { '1', '', '' }, { '2', 'value', 'end' } } },
    { name = 'MySQL TSV single column including an empty row', db = 'mysql',
      lines = { 'value', '', 'hello' }, headers = { 'value' }, rows = { { '' }, { 'hello' } } },
    { name = 'MySQL TSV whitespace and literal pipes', db = 'mysql',
      lines = { 'value', '  a|b  ' }, headers = { 'value' }, rows = { { '  a|b  ' } } },
    { name = 'MySQL TSV empty header positions', db = 'mysql',
      lines = { '\tid\t', '\t1\t' }, headers = { '(column-1)', 'id', '(column-3)' },
      rows = { { '', '1', '' } } },
    { name = 'MySQL table blank fields', db = 'mysql',
      lines = { '+----+--------+------+', '| id | middle | last |', '+----+--------+------+', '| 1  |        |      |', '+----+--------+------+', '1 row in set' },
      headers = { 'id', 'middle', 'last' }, rows = { { '1', '', '' } } },
    { name = 'PostgreSQL blank middle and trailing fields', db = 'postgresql',
      lines = { ' id | middle | last ', '----+--------+------', ' 1  |        |      ', '(1 row)' },
      headers = { 'id', 'middle', 'last' }, rows = { { '1', '', '' } } },
    { name = 'PostgreSQL empty single-column row', db = 'postgresql',
      lines = { ' value ', '-------', '', '(1 row)' }, headers = { 'value' }, rows = { { '' } } },
  }

  for _, fixture in ipairs(fixtures) do
    it('preserves ' .. fixture.name, function()
      local result = parser.parse(fixture.lines, fixture.db)
      assert.are.same(fixture.headers, result.headers)
      assert.are.same(fixture.rows, result.rows)
      local _, map = require('enhance.formatter').format(result)
      local rows = {}
      for line, entry in pairs(map) do rows[#rows + 1] = { line = line, values = entry.values } end
      table.sort(rows, function(a, b) return a.line < b.line end)
      for index, row in ipairs(rows) do assert.are.same(fixture.rows[index], row.values) end
      assert.equals(#fixture.rows, #rows)
    end)
  end

  it('copies parsed blank positions rather than shifted values', function()
    local result = parser.parse({ 'id\tmiddle\tlast', '1\t\tlast-value' }, 'mysql')
    local lines, map = require('enhance.formatter').format(result)
    local buf = vim.api.nvim_create_buf(false, true)
    local previous = vim.api.nvim_get_current_buf()
    local register = vim.fn.getreg('"')
    local register_type = vim.fn.getregtype('"')
    local plus, plus_type = vim.fn.getreg('+'), vim.fn.getregtype('+')
    local ok, err = pcall(function()
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'enhance-results'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.b[buf].enhance_result_rows = map
      vim.api.nvim_win_set_cursor(0, { 3, 2 })
      require('enhance.results').copy_row()
      assert.equals('1\t\tlast-value', vim.fn.getreg('"'))
    end)
    vim.fn.setreg('+', plus, plus_type)
    vim.fn.setreg('"', register, register_type)
    vim.api.nvim_set_current_buf(previous)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_true(ok, tostring(err))
  end)

  for _, backend in ipairs({ 'mysql', 'postgres' }) do
    it('retains empty lines from synchronous ' .. backend .. ' output', function()
      local original_system, original_spawn = vim.fn.system, vim.system
      local installer = require('enhance.helper_install')
      local original_path = installer.path
      installer.path = function() return '/verified/helper' end
      vim.fn.system = function() error('synchronous SQL must not use ambiguous CLI output') end
      vim.system = function(_, opts)
        assert.equals('SELECT value FROM t;', vim.json.decode(opts.stdin).query)
        return { wait = function() return { code = 0, signal = 0, stdout = vim.json.encode({ protocol = 1, ok = true,
          resultSets = { { columns = { { name = 'value', type = 'text' } }, rows = { { '' }, { 'hello' } } } },
          messages = {}, errors = {}, affectedRows = vim.NIL, durationMs = 1 }) } end }
      end
      local ok, result = pcall(function()
        local parsed = require('enhance.db.' .. backend).execute_single({ host = 'unused', database = 'unused', user = 'reader' }, 'SELECT value FROM t;')
        assert.are.same({ { '' }, { 'hello' } }, parsed.rows)
      end)
      vim.fn.system = original_system
      vim.system, installer.path = original_spawn, original_path
      assert.is_true(ok, tostring(result))
    end)

    it('retains empty values from structured ' .. backend .. ' output', function()
      local original_runner = package.loaded['enhance.helper_runner']
      local original_config = package.loaded['enhance.config']
      local original_results = package.loaded['enhance.results']
      local received
      package.loaded['enhance.config'] = { get = function() return true end }
      package.loaded['enhance.results'] = { display = function(_, _, _, metadata) received = metadata.parsed_result end }
      package.loaded['enhance.helper_runner'] = { new = function()
        return { run = function(_, _, _, callback)
          callback({ ok = true, parsed_result = { headers = { 'value' }, rows = { { '' }, { 'hello' } },
            metadata = { transport = 'helper' } }, messages = {}, errors = {}, affected_rows = vim.NIL, duration_ms = 1 })
        end, cancel = function() return true end }
      end }
      local ok, err = pcall(function()
        require('enhance.executor')['execute_' .. backend]({ type = backend, name = 'Fidelity', database = 'unused' }, 'SELECT value FROM t;')
        assert.are.same({ { '' }, { 'hello' } }, received.rows)
      end)
      require('enhance.executor').cancel_query()
      package.loaded['enhance.helper_runner'] = original_runner
      package.loaded['enhance.config'] = original_config
      package.loaded['enhance.results'] = original_results
      assert.is_true(ok, tostring(err))
    end)
  end
end)
