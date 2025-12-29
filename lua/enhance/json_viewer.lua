-- enhance.nvim - JSON Viewer
-- Floating window for viewing and navigating JSON fields

local M = {}
local json_utils = require("enhance.json_utils")

-- Persistent state
local state = {
  buf = nil,           -- Persistent buffer for JSON content
  win = nil,           -- Current floating window (if open)
  rows = nil,          -- All rows from parsed_result
  col_idx = nil,       -- Current column index
  row_idx = nil,       -- Current row index
  total_rows = nil,    -- Total number of rows
  json_columns = nil,  -- Map of column indices that contain JSON
  headers = nil,       -- Column headers for title display
}

---Check if we're in a results buffer and get cell data
---@return boolean is_results_buffer
---@return string|nil cell_value
---@return number|nil row_idx
---@return number|nil col_idx
local function get_current_cell_info()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Check if this is a results buffer
  if vim.bo[bufnr].filetype ~= 'enhance-results' then
    return false, nil, nil, nil
  end

  -- Get cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]

  -- Get config to determine data start line
  local config = require("enhance").get_config()
  -- Status line (2 lines if enabled at top) + header (1) + separator (1) = 4
  -- Then actual data starts at line 5
  local data_start_line = 5  -- Default: status (2) + header (1) + separator (1) + first data row
  if not (config.status_line and config.status_line.enabled and config.status_line.position == 'top') then
    data_start_line = 3  -- Just header + separator + first data row
  end

  -- Check if cursor is on a data row
  if line_num < data_start_line then
    return true, nil, nil, nil  -- In results buffer but not on data row
  end

  -- Calculate row index (1-based for Lua array access)
  -- data_start_line is the first data row (line 4 in this case)
  -- So line 4 = row 1, line 5 = row 2, etc.
  local row_idx = line_num - data_start_line + 1

  -- Get the line content
  local line = vim.api.nvim_get_current_line()

  -- Find all pipe positions
  local pipe_positions = {}
  for i = 1, #line do
    if line:sub(i, i) == '|' then
      table.insert(pipe_positions, i)
    end
  end

  -- Get cursor column (0-based)
  local col_pos = cursor[2]

  -- Find which cell the cursor is in based on pipe positions
  local col_idx = nil
  for i = 1, #pipe_positions - 1 do
    local start_pos = pipe_positions[i]
    local end_pos = pipe_positions[i + 1]

    -- Cursor is between these two pipes (0-based cursor position)
    if col_pos >= start_pos and col_pos < end_pos then
      col_idx = i  -- This is the column index (1-based, but first is empty)
      break
    end
  end

  if not col_idx or col_idx == 0 then
    return true, nil, nil, nil
  end

  -- Extract cell value between the pipes
  local start_pipe = pipe_positions[col_idx]
  local end_pipe = pipe_positions[col_idx + 1]
  local cell_value = vim.trim(line:sub(start_pipe + 1, end_pipe - 1))

  return true, cell_value, row_idx, col_idx
end

---Create or get the persistent JSON buffer
---@return number bufnr
local function get_or_create_buffer()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return state.buf
  end

  -- Create new buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].filetype = 'json'
  vim.bo[state.buf].bufhidden = 'hide'

  return state.buf
end

---Load JSON content into buffer
---@param json_str string JSON string to parse and display
---@param row_idx number Current row index
---@param total_rows number Total number of rows
local function load_json_content(json_str, row_idx, total_rows)
  local bufnr = get_or_create_buffer()

  -- Validate JSON
  local is_json = json_utils.is_json(json_str)

  if not is_json then
    -- Not valid JSON, show error
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Error: Not valid JSON" })
    return false
  end

  -- Pretty print JSON (preserves key order)
  local formatted = json_utils.pretty_print_string(json_str)
  local lines = vim.split(formatted, "\n")

  -- Set buffer content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Store metadata for navigation
  vim.api.nvim_buf_set_var(bufnr, 'enhance_json_row_idx', row_idx)
  vim.api.nvim_buf_set_var(bufnr, 'enhance_json_total_rows', total_rows)

  return true
end

---Show floating window with JSON content
local function show_floating_window()
  local bufnr = get_or_create_buffer()
  
  -- Check if buffer has content
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 or (line_count == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == "") then
    -- No content, silent fail
    return
  end
  
  -- Close existing window if open
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  
  -- Calculate window size (80% of screen, with max constraints)
  local width = math.min(80, math.floor(vim.o.columns * 0.8))
  local height = math.min(40, math.floor(vim.o.lines * 0.8))

  -- Get row info for title
  local row_idx = vim.api.nvim_buf_get_var(bufnr, 'enhance_json_row_idx')
  local total_rows = vim.api.nvim_buf_get_var(bufnr, 'enhance_json_total_rows')
  local col_name = state.headers and state.col_idx and state.headers[state.col_idx] or ""
  local title = col_name ~= ""
    and string.format(" JSON View - %s (Row %d/%d) ", col_name, row_idx, total_rows)
    or string.format(" JSON View - Row %d/%d ", row_idx, total_rows)

  -- Build footer with navigation hints
  local footer_parts = { " q: close", "<C-n>: next", "<C-p>: prev" }

  -- Add column navigation if multiple JSON columns exist
  if state.json_columns and vim.tbl_count(state.json_columns) > 1 then
    table.insert(footer_parts, "<C-h>/<C-l>: columns")
  end

  local footer = " " .. table.concat(footer_parts, " | ") .. " "

  -- Create floating window (right-aligned like scratch-manager)
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = 1,
    col = vim.o.columns - width,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
    footer = footer,
    footer_pos = "center",
  }
  
  state.win = vim.api.nvim_open_win(bufnr, true, win_opts)

  -- Apply custom highlights (matching scratch-manager style)
  vim.api.nvim_set_option_value(
    "winhighlight",
    "FloatBorder:EnhanceJsonBorder,FloatTitle:EnhanceJsonTitle,FloatFooter:EnhanceJsonFooter",
    { win = state.win }
  )

  -- Enable line numbers in the floating window
  vim.wo[state.win].number = true
  vim.wo[state.win].relativenumber = false
  
  -- Set buffer-local keymaps
  vim.keymap.set('n', 'q', function() M.close() end, { buffer = bufnr, nowait = true })
  vim.keymap.set('n', '<Esc>', function() M.close() end, { buffer = bufnr, nowait = true })
  vim.keymap.set('n', '<C-n>', function() M.navigate_next() end, { buffer = bufnr, nowait = true })
  vim.keymap.set('n', '<C-p>', function() M.navigate_prev() end, { buffer = bufnr, nowait = true })
  vim.keymap.set('n', '<C-l>', function() M.navigate_next_column() end, { buffer = bufnr, nowait = true })
  vim.keymap.set('n', '<C-h>', function() M.navigate_prev_column() end, { buffer = bufnr, nowait = true })
end

---Close the floating window
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
end

---Navigate to next row (same column)
function M.navigate_next()
  if not state.rows or not state.row_idx or not state.col_idx then
    return
  end

  -- Move to next row (wrap around)
  local next_row_idx = state.row_idx + 1
  if next_row_idx > state.total_rows then
    next_row_idx = 1  -- Wrap to first row
  end

  -- Load JSON from next row
  local json_value = state.rows[next_row_idx][state.col_idx]
  if json_value then
    load_json_content(json_value, next_row_idx, state.total_rows)
    state.row_idx = next_row_idx

    -- Update window title (preserve center alignment)
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local col_name = state.headers and state.headers[state.col_idx] or "Column " .. state.col_idx
      local title = string.format(" JSON View - %s (Row %d/%d) ", col_name, next_row_idx, state.total_rows)
      vim.api.nvim_win_set_config(state.win, { title = title, title_pos = "center" })
    end
  end
end

---Navigate to previous row (same column)
function M.navigate_prev()
  if not state.rows or not state.row_idx or not state.col_idx then
    return
  end

  -- Move to previous row (wrap around)
  local prev_row_idx = state.row_idx - 1
  if prev_row_idx < 1 then
    prev_row_idx = state.total_rows  -- Wrap to last row
  end

  -- Load JSON from previous row
  local json_value = state.rows[prev_row_idx][state.col_idx]
  if json_value then
    load_json_content(json_value, prev_row_idx, state.total_rows)
    state.row_idx = prev_row_idx

    -- Update window title (preserve center alignment)
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local col_name = state.headers and state.headers[state.col_idx] or "Column " .. state.col_idx
      local title = string.format(" JSON View - %s (Row %d/%d) ", col_name, prev_row_idx, state.total_rows)
      vim.api.nvim_win_set_config(state.win, { title = title, title_pos = "center" })
    end
  end
end

---Main entry point: Show JSON viewer
---Tries to load cell under cursor if in results buffer, otherwise shows last content
function M.show()
  -- Try to get current cell info
  local is_results, cell_value, row_idx, col_idx = get_current_cell_info()

  if is_results and row_idx and col_idx then
    -- We're in results buffer on a cell - get actual data from buffer metadata
    local bufnr = vim.api.nvim_get_current_buf()
    local ok, parsed_result = pcall(vim.api.nvim_buf_get_var, bufnr, 'enhance_parsed_result')
    local ok2, json_columns = pcall(vim.api.nvim_buf_get_var, bufnr, 'enhance_json_columns')

    if ok and ok2 and parsed_result and json_columns then
      -- Check if this column is a JSON column
      if json_columns[col_idx] then
        -- Get actual cell value from parsed_result (not truncated display)
        local actual_value = parsed_result.rows[row_idx][col_idx]

        if actual_value then
          -- Load this JSON into buffer
          local total_rows = #parsed_result.rows
          load_json_content(actual_value, row_idx, total_rows)

          -- Store state for navigation
          state.rows = parsed_result.rows
          state.row_idx = row_idx
          state.col_idx = col_idx
          state.total_rows = total_rows
          state.json_columns = json_columns
          state.headers = parsed_result.headers
        end
      end
    end
  end

  -- Show floating window (with current or last content)
  show_floating_window()
end

---Navigate to next JSON column (same row)
function M.navigate_next_column()
  if not state.rows or not state.row_idx or not state.json_columns then
    return
  end

  -- Get list of JSON column indices (sorted)
  local json_col_indices = {}
  for col_idx, is_json in pairs(state.json_columns) do
    if is_json then
      table.insert(json_col_indices, col_idx)
    end
  end
  table.sort(json_col_indices)

  if #json_col_indices <= 1 then
    return  -- Only one JSON column, nothing to navigate to
  end

  -- Find current position in the list
  local current_pos = nil
  for i, col_idx in ipairs(json_col_indices) do
    if col_idx == state.col_idx then
      current_pos = i
      break
    end
  end

  if not current_pos then
    return
  end

  -- Move to next column (wrap around)
  local next_pos = current_pos + 1
  if next_pos > #json_col_indices then
    next_pos = 1
  end

  local next_col_idx = json_col_indices[next_pos]

  -- Load JSON from same row, different column
  local json_value = state.rows[state.row_idx][next_col_idx]
  if json_value then
    load_json_content(json_value, state.row_idx, state.total_rows)
    state.col_idx = next_col_idx

    -- Update window title
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local col_name = state.headers and state.headers[next_col_idx] or "Column " .. next_col_idx
      local title = string.format(" JSON View - %s (Row %d/%d) ", col_name, state.row_idx, state.total_rows)
      vim.api.nvim_win_set_config(state.win, { title = title, title_pos = "center" })
    end
  end
end

---Navigate to previous JSON column (same row)
function M.navigate_prev_column()
  if not state.rows or not state.row_idx or not state.json_columns then
    return
  end

  -- Get list of JSON column indices (sorted)
  local json_col_indices = {}
  for col_idx, is_json in pairs(state.json_columns) do
    if is_json then
      table.insert(json_col_indices, col_idx)
    end
  end
  table.sort(json_col_indices)

  if #json_col_indices <= 1 then
    return  -- Only one JSON column, nothing to navigate to
  end

  -- Find current position in the list
  local current_pos = nil
  for i, col_idx in ipairs(json_col_indices) do
    if col_idx == state.col_idx then
      current_pos = i
      break
    end
  end

  if not current_pos then
    return
  end

  -- Move to previous column (wrap around)
  local prev_pos = current_pos - 1
  if prev_pos < 1 then
    prev_pos = #json_col_indices
  end

  local prev_col_idx = json_col_indices[prev_pos]

  -- Load JSON from same row, different column
  local json_value = state.rows[state.row_idx][prev_col_idx]
  if json_value then
    load_json_content(json_value, state.row_idx, state.total_rows)
    state.col_idx = prev_col_idx

    -- Update window title
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local col_name = state.headers and state.headers[prev_col_idx] or "Column " .. prev_col_idx
      local title = string.format(" JSON View - %s (Row %d/%d) ", col_name, state.row_idx, state.total_rows)
      vim.api.nvim_win_set_config(state.win, { title = title, title_pos = "center" })
    end
  end
end

-- Expose internal functions for testing
M._get_current_cell_info = get_current_cell_info
M._load_json_content = load_json_content

return M

