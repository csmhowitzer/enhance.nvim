-- enhance.nvim - Results display
-- Handles displaying query results in buffers

local M = {}

---Format number with comma separators (e.g., 1000 -> 1,000)
---@param num number Number to format
---@return string Formatted number string
local function format_number(num)
  local formatted = tostring(num)
  -- Add commas for thousands separators
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if k == 0 then
      break
    end
  end
  return formatted
end

---Generate status line from metadata
---@param metadata table Execution metadata
---@return string[] Status line (2 lines: info, separator)
---@return table Highlight positions for granular coloring
local function generate_status_line(metadata)
  -- Build info line with parts
  local parts = {
    { text = "Rows: ", type = "label" },
    { text = metadata.row_count and format_number(metadata.row_count) or "N/A", type = "value" },
    { text = " | ", type = "label" },
    { text = string.format("%.2fms", metadata.execution_time), type = "value" },
    { text = " | ", type = "label" },
    { text = metadata.connection_name, type = "connection" },
    { text = " | ", type = "label" },
    { text = metadata.db_type, type = "db_type" },
    { text = " | ", type = "label" },
    { text = metadata.timestamp, type = "timestamp" },
  }

  -- Build full info line and track positions for highlighting
  local info = ""
  local highlights = {}

  for _, part in ipairs(parts) do
    local start_col = #info
    info = info .. part.text
    local end_col = #info
    table.insert(highlights, {
      type = part.type,
      start_col = start_col,
      end_col = end_col,
    })
  end

  -- Make separator match the length of the info line
  local separator = string.rep("─", #info)

  return { info, separator }, highlights
end

---Apply highlight to status line in buffer
---@param bufnr number Buffer number
---@param config table Plugin configuration
---@param position string Status line position ('top' or 'bottom')
---@param highlights table Highlight positions from generate_status_line
local function apply_status_line_highlight(bufnr, config, position, highlights)
  -- Create namespace for status line highlights
  local ns_id = vim.api.nvim_create_namespace('enhance_status_line')

  -- Determine which line is the info line based on position
  local info_line, separator_line
  if position == 'top' then
    info_line = 0      -- First line (0-indexed)
    separator_line = 1 -- Second line (0-indexed)
  else  -- bottom
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    info_line = line_count - 2
    separator_line = line_count - 1
  end

  -- Apply granular highlights to info line
  for _, hl in ipairs(highlights) do
    local hl_group = config.status_line.highlights[hl.type]
    if hl_group then
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, info_line, hl.start_col, hl.end_col)
    end
  end

  -- Apply separator highlight to separator line
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, config.status_line.highlights.separator, separator_line, 0, -1)
end

---Setup dynamic cursor line highlighting that changes on every 5th row
---@param bufnr number Buffer number
---@param win number Window number
function M.setup_dynamic_cursorline(bufnr, win)
  -- Create autocmd group for this specific buffer
  local group_name = string.format("EnhanceCursorLine_%d", bufnr)
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })

  -- Function to update cursor line highlight based on current line
  local function update_cursorline_highlight()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end

    local cursor = vim.api.nvim_win_get_cursor(win)
    local line = cursor[1]

    -- Lines 1-4 are status/header, data rows start at line 5
    if line <= 4 then
      vim.wo[win].winhighlight = 'CursorLine:EnhanceCursorLine'
      return
    end

    -- Calculate data row number (line 5 = row 1, line 6 = row 2, etc.)
    local row_num = line - 4

    -- Every 5th row gets accent color
    if row_num % 5 == 0 then
      vim.wo[win].winhighlight = 'CursorLine:EnhanceCursorLineAccent'
    else
      vim.wo[win].winhighlight = 'CursorLine:EnhanceCursorLine'
    end
  end

  -- Update on cursor movement
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = bufnr,
    callback = update_cursorline_highlight,
  })

  -- Initial update
  update_cursorline_highlight()
end

---Display query results in a buffer
---@param lines string[] Result lines
---@param connection table Database connection
---@param query_bufnr number? Query buffer number (optional, for associating results)
---@param metadata table? Execution metadata (execution_time, row_count, db_type, timestamp, connection_name)
function M.display(lines, connection, query_bufnr, metadata)
  local explorer = require("enhance.explorer")
  local timestamp = os.date("%H:%M:%S")
  local config = require("enhance").get_config()

  -- Generate and insert status line if metadata is provided
  local status_highlights = nil
  if metadata and config.status_line.enabled and config.status_line.position ~= 'none' then
    local status_lines, highlights = generate_status_line(metadata)
    status_highlights = highlights

    if config.status_line.position == 'top' then
      -- Insert at beginning
      for i = #status_lines, 1, -1 do
        table.insert(lines, 1, status_lines[i])
      end
    elseif config.status_line.position == 'bottom' then
      -- Append at end
      for _, line in ipairs(status_lines) do
        table.insert(lines, line)
      end
    end
  end

  -- Check if query buffer already has an associated result buffer
  local buf
  if query_bufnr then
    local existing_result_bufnr = explorer.get_result_buffer_info(query_bufnr)
    if existing_result_bufnr and vim.api.nvim_buf_is_valid(existing_result_bufnr) then
      -- Reuse existing result buffer - update its content
      buf = existing_result_bufnr
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
    end
  end

  -- Create new result buffer if we don't have one to reuse
  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = 'enhance-results'
    vim.bo[buf].modifiable = false

    -- Set buffer name with timestamp
    local buf_name = string.format("[enhance-results] %s (%s)", connection.name, timestamp)
    local ok, err = pcall(vim.api.nvim_buf_set_name, buf, buf_name)
    if not ok then
      vim.notify("Failed to set results buffer name: " .. tostring(err), vim.log.levels.ERROR)
    end
  end

  -- Associate result buffer with query buffer
  if query_bufnr then
    explorer.associate_result_buffer(query_bufnr, buf, timestamp)
  end

  -- Get or create results window
  local results_win = explorer.get_results_window()

  -- Check if results window is still valid
  if results_win and vim.api.nvim_win_is_valid(results_win) then
    -- Reuse existing results window - just switch buffer
    vim.api.nvim_win_set_buf(results_win, buf)
  else
    -- Create new results window (bottom split from query editor)
    -- Get UI configuration
    local config = require("enhance").get_config()

    -- Open in configured position
    if config.ui.results_position == "vsplit" then
      vim.cmd('vsplit')
    elseif config.ui.results_position == "tab" then
      vim.cmd('tabnew')
    else
      vim.cmd('split')
    end

    results_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(results_win, buf)

    -- Track the results window
    explorer.set_results_window(results_win)
  end

  -- Set buffer-local window options for results window
  if results_win and vim.api.nvim_win_is_valid(results_win) then
    -- Disable relative line numbers (use absolute)
    vim.wo[results_win].relativenumber = false
    vim.wo[results_win].number = true

    -- Remove vertical line (colorcolumn)
    vim.wo[results_win].colorcolumn = ""

    -- Custom line numbering: offset to start at 1 on first data row (line 3)
    -- Lines 1-2 (status line) show no numbers, line 3+ shows 1, 2, 3...
    vim.wo[results_win].statuscolumn = '%{%v:lua.require("enhance.results")._line_number()%}'

    -- Enable cursorline and use custom highlight
    vim.wo[results_win].cursorline = true
    vim.wo[results_win].winhighlight = 'CursorLine:EnhanceCursorLine'

    -- Setup dynamic cursor line color that changes on every 5th row
    M.setup_dynamic_cursorline(buf, results_win)
  end

  -- Set keymaps
  M.setup_keymaps(buf)

  -- Apply status line highlight if metadata is provided
  -- Use vim.schedule to ensure highlights are applied after buffer is fully rendered
  if metadata and config.status_line.enabled and config.status_line.position ~= 'none' and status_highlights then
    vim.schedule(function()
      -- Re-define highlights to ensure they exist (in case colorscheme changed)
      require("enhance").setup_highlights()
      apply_status_line_highlight(buf, config, config.status_line.position, status_highlights)
    end)
  end

  vim.notify("Query results displayed", vim.log.levels.INFO)

  -- Refresh explorer to show updated results timestamp
  -- Use vim.schedule to defer UI update to main event loop (we're in async callback)
  vim.schedule(function()
    explorer.refresh_explorer()
  end)
end

---Display a message in the results window (for errors, warnings, etc.)
---@param lines string[] Message lines to display
function M.display_message(lines)
  -- Create message buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = 'enhance-results'
  pcall(vim.api.nvim_buf_set_name, buf, '[Enhance] Message')

  -- Set message content BEFORE making it non-modifiable
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Get or create results window
  local explorer = require("enhance.explorer")
  local results_win = explorer.get_results_window()

  -- Check if results window is still valid
  if results_win and vim.api.nvim_win_is_valid(results_win) then
    -- Reuse existing results window - just switch buffer
    vim.api.nvim_win_set_buf(results_win, buf)
  else
    -- Create new results window (bottom split from query editor)
    vim.cmd('split')
    results_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(results_win, buf)

    -- Track the results window
    explorer.set_results_window(results_win)
  end

  -- Set keymaps
  M.setup_keymaps(buf)
end

---Setup keymaps for results buffer
---@param bufnr integer Buffer number
function M.setup_keymaps(bufnr)
  -- Close buffer
  vim.keymap.set('n', 'q', function()
    vim.cmd('close')
  end, { buffer = bufnr, desc = "Close results" })

  -- Refresh (re-execute last query)
  vim.keymap.set('n', 'r', function()
    vim.notify("Refresh not yet implemented", vim.log.levels.WARN)
  end, { buffer = bufnr, desc = "Refresh results" })
end

---Custom line number function for statuscolumn
---Lines 1-4 (status line + header) show no numbers
---Line 5+ (data rows) show offset numbers starting at 1
---Every 5th line gets a different highlight color
---@return string Line number text with highlight
function M._line_number()
  local line = vim.v.lnum

  -- No numbers for status line (1-2) and header row (3-4)
  if line <= 4 then
    return ""
  end

  -- Data rows: offset to start at 1
  local row_num = line - 4

  -- Get config for highlight groups
  local config = require("enhance").get_config()
  local hl_group

  -- Every 5th line gets accent color
  if row_num % 5 == 0 then
    hl_group = config.status_line.highlights.line_number_accent or "EnhanceLineNumberAccent"
  else
    hl_group = config.status_line.highlights.line_number or "EnhanceLineNumber"
  end

  -- Return with highlight: %#HighlightGroup#text
  return string.format("%%#%s#%4d ", hl_group, row_num)
end

-- Expose for testing
M._setup_keymaps = M.setup_keymaps

return M

