describe('query SQL preservation', function()
  local query, buf, executor, original_executor, original_results

  before_each(function()
    query = require('enhance.query')
    original_executor = package.loaded['enhance.executor']
    original_results = package.loaded['enhance.results']
    executor = { execute = function() end }
    package.loaded['enhance.executor'] = executor
    buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].enhance_connection = { name = 'Preservation', type = 'sqlite', path = 'unused.db' }
  end)

  after_each(function()
    package.loaded['enhance.executor'] = original_executor
    package.loaded['enhance.results'] = original_results
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('passes literals, comments, and whitespace unchanged to execution', function()
    local lines = { '  -- keep this comment', "SELECT 'a--b', 'it''s--safe';", 'SELECT 2;  ' }
    local received
    executor.execute = function(_, text) received = text end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    query.execute_current_query(buf)
    assert.equals(table.concat(lines, '\n'), received)
  end)

  it('passes visual SQL unchanged, including surrounding whitespace', function()
    local text = "  SELECT 'a--b';  "
    local received
    executor.execute = function(_, sql) received = sql end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
    vim.api.nvim_buf_set_mark(buf, '<', 1, 0, {})
    vim.api.nvim_buf_set_mark(buf, '>', 1, #text - 1, {})
    local previous = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_current_buf(buf)
    query.execute_visual_selection(buf)
    vim.api.nvim_set_current_buf(previous)
    assert.equals(text, received)
  end)

  it('does not execute whitespace-only input', function()
    local calls = 0
    executor.execute = function() calls = calls + 1 end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '  ', '\t' })
    query.execute_current_query(buf)
    assert.equals(0, calls)
  end)
end)
