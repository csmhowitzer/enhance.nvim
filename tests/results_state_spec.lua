describe('result buffer render ownership', function()
  it('clears JSON metadata and ignores highlights scheduled by an older render', function()
    local results = require('enhance.results')
    local old_explorer, old_schedule, old_notify = package.loaded['enhance.explorer'], vim.schedule, vim.notify
    local old_error = results.apply_error_highlighting
    local previous_buf = vim.api.nvim_get_current_buf()
    local query = vim.api.nvim_create_buf(false, true)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = 'enhance-results'
    local queued, error_calls = {}, 0
    package.loaded['enhance.explorer'] = {
      get_result_buffer_info = function() return buf end,
      associate_result_buffer = function() end,
      get_results_window = function() return vim.api.nvim_get_current_win() end,
      refresh_explorer = function() end,
    }
    vim.schedule = function(fn) queued[#queued + 1] = fn end
    vim.notify = function() end
    results.apply_error_highlighting = function() error_calls = error_calls + 1 end
    local connection = { type = 'sqlite', name = 'test' }
    local base = { execution_time = 1, row_count = 1, connection_name = 'test',
      db_type = 'sqlite', timestamp = '12:00:00' }
    local ok, err = pcall(function()
      local first = vim.tbl_extend('force', base, { is_error = true,
        parsed_result = { headers = { 'payload' }, rows = { { '{"a":1}' } } } })
      results.display({ '| payload |', '| ------- |', '| {"a":1} |' }, connection, query, first)
      local old_callbacks = vim.list_extend({}, queued)
      assert.is_true(pcall(vim.api.nvim_buf_get_var, buf, 'enhance_parsed_result'))
      results.display({ 'Query Execution Failed' }, connection, query, base)
      assert.is_false(pcall(vim.api.nvim_buf_get_var, buf, 'enhance_parsed_result'))
      assert.is_false(pcall(vim.api.nvim_buf_get_var, buf, 'enhance_json_columns'))
      for _, callback in ipairs(old_callbacks) do callback() end
      assert.equals(0, error_calls)
    end)
    results.apply_error_highlighting = old_error
    package.loaded['enhance.explorer'], vim.schedule, vim.notify = old_explorer, old_schedule, old_notify
    vim.api.nvim_win_set_buf(0, previous_buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.api.nvim_buf_delete(query, { force = true })
    if not ok then error(err) end
  end)
end)

describe('result set header colors', function()
  it('colors rendered headers for one statement and clears them on buffer reuse', function()
    local results = require('enhance.results')
    local old_explorer, old_enhance = package.loaded['enhance.explorer'], package.loaded['enhance']
    local old_schedule, old_notify = vim.schedule, vim.notify
    local previous_buf = vim.api.nvim_get_current_buf()
    local query = vim.api.nvim_create_buf(false, true)
    local buf = vim.api.nvim_create_buf(false, true)
    local queued = {}
    local config = { status_line = { enabled = true, position = 'top', highlights = {
      label = 'EnhanceStatusLabel', value = 'EnhanceStatusValue', separator = 'EnhanceStatusSeparator',
    } }, ui = { results_position = 'split' } }
    package.loaded['enhance'] = { get_config = function() return config end, setup_highlights = function() end }
    package.loaded['enhance.explorer'] = {
      get_result_buffer_info = function() return buf end,
      associate_result_buffer = function() end,
      get_results_window = function() return vim.api.nvim_get_current_win() end,
      refresh_explorer = function() end,
    }
    vim.schedule = function(fn) queued[#queued + 1] = fn end
    vim.notify = function() end
    local metadata = { execution_time = 1, row_count = 0, statement_count = 1,
      connection_name = 'test', db_type = 'sqlite', timestamp = '12:00:00' }
    local ns = vim.api.nvim_create_namespace('enhance_result_set_headers')
    local function marks()
      return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    end
    local ok, err = pcall(function()
      results.display({ 'Result Set 1/2', '', 'Result Set 2/2' },
        { type = 'sqlite', name = 'test' }, query, metadata)
      for _, callback in ipairs(queued) do callback() end
      assert.is_true(#marks() >= 4, 'both result set headers should have label and value colors')
      queued = {}
      results.display({ 'No results' }, { type = 'sqlite', name = 'test' }, query, metadata)
      for _, callback in ipairs(queued) do callback() end
      assert.equals(0, #marks(), 'old result set header colors should not survive buffer reuse')
    end)
    package.loaded['enhance.explorer'], package.loaded['enhance'] = old_explorer, old_enhance
    vim.schedule, vim.notify = old_schedule, old_notify
    vim.api.nvim_win_set_buf(0, previous_buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.api.nvim_buf_delete(query, { force = true })
    if not ok then error(err) end
  end)
end)
