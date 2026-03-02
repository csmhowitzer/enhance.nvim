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
  local parts = {}

  -- For multiple statements: show "Statements: X | Rows: Y | ..."
  -- For single statement: show "Rows: X | ..."
  -- Pad first part to 15 chars to align pipe with per-result-set headers
  if metadata.statement_count and metadata.statement_count > 1 then
    -- Multiple statements
    local first_part = "Statements: " .. tostring(metadata.statement_count)
    local padding = string.rep(" ", math.max(0, 15 - #first_part))

    table.insert(parts, { text = "Statements: ", type = "label" })
    table.insert(parts, { text = tostring(metadata.statement_count), type = "value" })
    table.insert(parts, { text = padding, type = "label" })
    table.insert(parts, { text = "| ", type = "label" })

    -- Show total table rows if any
    if metadata.total_table_rows and metadata.total_table_rows > 0 then
      table.insert(parts, { text = "Rows: ", type = "label" })
      table.insert(parts, { text = format_number(metadata.total_table_rows), type = "value" })
      table.insert(parts, { text = " | ", type = "label" })
    end
  else
    -- Single statement
    table.insert(parts, { text = "Rows: ", type = "label" })
    table.insert(parts, { text = metadata.row_count and format_number(metadata.row_count) or "N/A", type = "value" })
    table.insert(parts, { text = " | ", type = "label" })
  end

  -- Common parts: execution time, connection, db type, timestamp
  table.insert(parts, { text = string.format("%.2fms", metadata.execution_time), type = "value" })
  table.insert(parts, { text = " | ", type = "label" })
  table.insert(parts, { text = metadata.connection_name, type = "connection" })
  table.insert(parts, { text = " | ", type = "label" })
  table.insert(parts, { text = metadata.db_type, type = "db_type" })
  table.insert(parts, { text = " | ", type = "label" })
  table.insert(parts, { text = metadata.timestamp, type = "timestamp" })

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
  if config.status_line and config.status_line.highlights then
    for _, hl in ipairs(highlights) do
      local hl_group = config.status_line.highlights[hl.type]
      if hl_group then
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, info_line, hl.start_col, hl.end_col)
      end
    end

    -- Apply separator highlight to separator line
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, config.status_line.highlights.separator, separator_line, 0, -1)
  end
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

    -- Get line number mapping from buffer variable
    local ok, mapping = pcall(vim.api.nvim_buf_get_var, bufnr, 'enhance_line_numbers')
    if not ok or not mapping then
      -- Fallback to default highlight if no mapping
      vim.wo[win].winhighlight = 'CursorLine:EnhanceCursorLine'
      return
    end

    -- Check if this line has a row number (is a data row)
    local row_num = mapping[line]
    if not row_num then
      -- Not a data row (header, separator, etc.)
      vim.wo[win].winhighlight = 'CursorLine:EnhanceCursorLine'
      return
    end

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

---Build line number mapping for data rows
---@param lines table Array of buffer lines
---@param config table Plugin configuration
---@return table Mapping of line_number -> row_number (1-based)
local function build_line_number_mapping(lines, config)
  local mapping = {}
  local in_data_section = false
  local current_row = 0

  -- Determine starting line based on status line position
  local start_line = 1
  if config.status_line and config.status_line.enabled and config.status_line.position == 'top' then
    start_line = 3  -- Skip status line (2 lines)
  end

  for i = start_line, #lines do
    local line = lines[i]

    -- Reset row counter when we hit a new "Result Set" header
    if line:match("^Result Set") then
      in_data_section = false
      current_row = 0
    -- Skip blank lines
    elseif line:match("^%s*$") then
      in_data_section = false
    -- Detect separator line (all dashes, spaces, and pipes)
    elseif line:match("^[-%s|]+$") then
      in_data_section = true
      current_row = 0
    -- Data rows come after separator
    elseif in_data_section then
      current_row = current_row + 1
      mapping[i] = current_row
    end
  end

  return mapping
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

  -- Count non-empty lines (excluding potential headers)
  local data_line_count = 0
  for _, line in ipairs(lines) do
    if line:match("%S") then
      data_line_count = data_line_count + 1
    end
  end

  -- Check if this is a DML/DDL statement with no result rows
  local is_non_select_statement = false

  if metadata and metadata.query_type then
    is_non_select_statement = true

    -- Generate appropriate message based on query type
    local message = ""
    if metadata.query_type == "CREATE_TABLE" then
      message = "✓ Table created successfully"
    elseif metadata.query_type == "DROP_TABLE" then
      message = "✓ Table dropped successfully"
    elseif metadata.query_type == "ALTER_TABLE" then
      message = "✓ Table altered successfully"
    elseif metadata.query_type == "INSERT" then
      message = string.format("✓ Inserted %s row%s",
        format_number(metadata.row_count),
        metadata.row_count == 1 and "" or "s")
    elseif metadata.query_type == "UPDATE" then
      message = string.format("✓ Updated %s row%s",
        format_number(metadata.row_count),
        metadata.row_count == 1 and "" or "s")
    elseif metadata.query_type == "DELETE" then
      message = string.format("✓ Deleted %s row%s",
        format_number(metadata.row_count),
        metadata.row_count == 1 and "" or "s")
    end

    -- Add message to output
    if message ~= "" and data_line_count == 0 then
      table.insert(lines, "")
      table.insert(lines, message)
      table.insert(lines, "")
    end
  end

  -- Generate and insert status line if metadata is provided
  local status_highlights = nil
  if metadata and config.status_line and config.status_line.enabled and config.status_line.position ~= 'none' then
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

  -- Build and store line number mapping for data rows
  local line_number_mapping = build_line_number_mapping(lines, config)
  vim.api.nvim_buf_set_var(buf, 'enhance_line_numbers', line_number_mapping)

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
    -- Move cursor to results window (ensures cursor moves on every execution)
    vim.api.nvim_set_current_win(results_win)
  else
    -- Create new results window (bottom split from query editor)
    -- Open in configured position
    if config.ui and config.ui.results_position == "vsplit" then
      vim.cmd('vsplit')
    elseif config.ui and config.ui.results_position == "tab" then
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
  if metadata and config.status_line and config.status_line.enabled and config.status_line.position ~= 'none' and status_highlights then
    vim.schedule(function()
      -- Re-define highlights to ensure they exist (in case colorscheme changed)
      require("enhance").setup_highlights()
      apply_status_line_highlight(buf, config, config.status_line.position, status_highlights)

      -- Apply result set highlighting in the same schedule call
      if metadata.statement_count and metadata.statement_count > 1 then
        M.apply_result_set_highlighting(buf, config)
      end
    end)
  end

  -- Detect JSON columns and apply highlighting
  local json_columns = nil
  if metadata and metadata.parsed_result then
    local detector = require("enhance.json_detector")

    -- Handle multiple result sets
    if metadata.parsed_result.multiple_results then
      json_columns = {}
      for i, result_set in ipairs(metadata.parsed_result.result_sets) do
        json_columns[i] = detector.detect_json_columns(
          result_set.headers,
          result_set.rows
        )
      end
    -- Handle single result set (backward compatibility)
    else
      json_columns = detector.detect_json_columns(
        metadata.parsed_result.headers,
        metadata.parsed_result.rows
      )
    end

    -- Store parsed_result in buffer for JSON viewer access
    vim.api.nvim_buf_set_var(buf, 'enhance_parsed_result', metadata.parsed_result)
    vim.api.nvim_buf_set_var(buf, 'enhance_json_columns', json_columns)
  end

  -- Apply error highlighting if this is an error display
  if metadata and metadata.is_error then
    vim.schedule(function()
      M.apply_error_highlighting(buf, config)
    end)
  end

  -- Apply NULL highlighting to result cells
  vim.schedule(function()
    M.apply_null_highlighting(buf, config)
  end)

  -- Apply JSON highlighting to detected JSON columns
  if json_columns then
    vim.schedule(function()
      M.apply_json_highlighting(buf, config, json_columns, metadata)
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
---@param is_error boolean? Whether this is an error message (for red highlighting)
function M.display_message(lines, is_error)
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
    -- Move cursor to results window (ensures cursor moves on every message display)
    vim.api.nvim_set_current_win(results_win)
  else
    -- Create new results window (bottom split from query editor)
    vim.cmd('split')
    results_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(results_win, buf)

    -- Track the results window
    explorer.set_results_window(results_win)
  end

  -- Apply error highlighting if this is an error message
  if is_error then
    local config = require("enhance").get_config()
    vim.schedule(function()
      M.apply_error_highlighting(buf, config)
    end)
  end

  -- Set keymaps
  M.setup_keymaps(buf)
end

---Setup keymaps for results buffer
---@param bufnr integer Buffer number
function M.setup_keymaps(bufnr)
  -- Refresh (re-execute last query)
  vim.keymap.set('n', 'r', function()
    vim.notify("Refresh not yet implemented", vim.log.levels.WARN)
  end, { buffer = bufnr, desc = "Refresh results" })

  -- Smart redirect :w to save associated query buffer
  -- Create buffer-local command
  vim.api.nvim_buf_create_user_command(bufnr, 'Write', function()
    M._save_query_from_results()
  end, { desc = "Save associated query buffer" })

  -- Create buffer-local abbreviation for :w -> :Write
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd([[cnoreabbrev <buffer> w Write]])
  end)
end

---Save query buffer from results buffer (called via :w abbreviation)
function M._save_query_from_results()
  local explorer = require('enhance.explorer')

  -- Get the currently visible editor buffer (not the associated query buffer)
  local query_bufnr = explorer.get_current_editor_buffer()
  if not query_bufnr or not vim.api.nvim_buf_is_valid(query_bufnr) then
    vim.notify("No query buffer visible in editor", vim.log.levels.WARN)
    return
  end

  -- Get query buffer filepath
  local query_filepath = vim.api.nvim_buf_get_name(query_bufnr)
  if not query_filepath or query_filepath == "" then
    vim.notify("Query buffer has no file", vim.log.levels.WARN)
    return
  end

  -- Check if it's a tmp file (needs save prompt) or saved query (direct save)
  local is_tmp = explorer.is_tmp_file(query_filepath)

  if is_tmp then
    -- Switch to query buffer and trigger save (will show prompt)
    local query_win = vim.fn.bufwinid(query_bufnr)
    if query_win ~= -1 then
      vim.api.nvim_set_current_win(query_win)
    end
    vim.cmd('write')
  else
    -- It's already a saved query, write it properly to update buffer state
    vim.api.nvim_buf_call(query_bufnr, function()
      vim.cmd('write!')  -- Use write! to force overwrite
    end)
    local filename = vim.fn.fnamemodify(query_filepath, ":t")
    vim.notify("Saved query: " .. filename, vim.log.levels.INFO)
  end
end



---Custom line number function for statuscolumn
---Uses buffer-local mapping to show row numbers only for data rows
---Each result set has its own numbering (1, 2, 3...)
---Every 5th line gets a different highlight color
---@return string Line number text with highlight
function M._line_number()
  local line = vim.v.lnum
  local bufnr = vim.api.nvim_get_current_buf()

  -- Get line number mapping from buffer variable
  local ok, mapping = pcall(vim.api.nvim_buf_get_var, bufnr, 'enhance_line_numbers')
  if not ok or not mapping then
    return ""
  end

  -- Check if this line has a row number
  local row_num = mapping[line]
  if not row_num then
    return ""
  end

  -- Get config for highlight groups
  local config = require("enhance").get_config()
  local hl_group

  -- Every 5th line gets accent color
  if row_num % 5 == 0 then
    hl_group = (config.status_line and config.status_line.highlights and config.status_line.highlights.line_number_accent) or "EnhanceLineNumberAccent"
  else
    hl_group = (config.status_line and config.status_line.highlights and config.status_line.highlights.line_number) or "EnhanceLineNumber"
  end

  -- Return with highlight: %#HighlightGroup#text
  return string.format("%%#%s#%4d ", hl_group, row_num)
end

---Apply error highlighting to error messages
---@param bufnr number Buffer number
---@param config table Plugin configuration
function M.apply_error_highlighting(bufnr, config)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Create namespace for error highlights
  local ns_id = vim.api.nvim_create_namespace('enhance_error_highlight')

  -- Get all lines in buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Determine data start line based on status line position
  local data_start_line = 0
  if config.status_line and config.status_line.enabled and config.status_line.position == 'top' then
    data_start_line = 2  -- Skip status line (2 lines)
  end

  -- Highlight all error lines (everything after status line)
  for line_num = data_start_line, #lines - 1 do
    vim.api.nvim_buf_add_highlight(
      bufnr,
      ns_id,
      'EnhanceError',
      line_num,
      0,
      -1
    )
  end
end

---Apply NULL highlighting to result buffer
---@param bufnr number Buffer number
---@param config table Plugin configuration
function M.apply_null_highlighting(bufnr, config)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Create namespace for NULL highlights
  local ns_id = vim.api.nvim_create_namespace('enhance_null_highlight')

  -- Get all lines in buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Determine data start line based on status line position
  local data_start_line = 0
  if config.status_line and config.status_line.enabled and config.status_line.position == 'top' then
    data_start_line = 2  -- Skip status line (2 lines)
  end

  -- Search for NULL values in each line and highlight them
  for line_num = data_start_line, #lines - 1 do
    local line = lines[line_num + 1]  -- Lua is 1-indexed, nvim is 0-indexed
    if line then
      -- Find all occurrences of " NULL " (with spaces to avoid partial matches)
      local start_pos = 1
      while true do
        local null_start, null_end = line:find(" NULL ", start_pos, true)
        if not null_start then
          break
        end
        -- Highlight the word NULL (excluding surrounding spaces)
        -- null_start points to the space before NULL, so add 1
        -- null_end points to the space after NULL, so subtract 1
        vim.api.nvim_buf_add_highlight(
          bufnr,
          ns_id,
          'EnhanceNull',
          line_num,
          null_start,  -- Start at space before NULL
          null_end - 1  -- End before space after NULL
        )
        start_pos = null_end + 1
      end
    end
  end
end

---Apply JSON highlighting to detected JSON columns
---@param bufnr number Buffer number
---@param config table Plugin configuration
---@param json_columns table<number, boolean>|table<number, table<number, boolean>> Map of column_index -> is_json_column, or array of such maps for multiple result sets
---@param metadata table? Metadata containing parsed_result info
function M.apply_json_highlighting(bufnr, config, json_columns, metadata)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Create namespace for JSON highlights
  local ns_id = vim.api.nvim_create_namespace('enhance_json_highlight')

  -- Get all lines in buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Check if we have multiple result sets
  local is_multiple = metadata and metadata.parsed_result and metadata.parsed_result.multiple_results

  if is_multiple then
    -- Handle multiple result sets - find each table and apply its JSON columns
    M._apply_json_highlighting_multiple(bufnr, ns_id, lines, json_columns, config)
  else
    -- Handle single result set (backward compatibility)
    M._apply_json_highlighting_single(bufnr, ns_id, lines, json_columns, config)
  end
end

---Apply JSON highlighting for a single result set
---@param bufnr number Buffer number
---@param ns_id number Namespace ID
---@param lines string[] Buffer lines
---@param json_columns table<number, boolean> Map of column_index -> is_json_column
---@param config table Plugin configuration
function M._apply_json_highlighting_single(bufnr, ns_id, lines, json_columns, config)
  -- Determine data start line based on status line position
  local data_start_line = 0
  if config.status_line and config.status_line.enabled and config.status_line.position == 'top' then
    data_start_line = 4  -- Skip status line (2 lines) + header (1 line) + separator (1 line)
  else
    data_start_line = 2  -- Skip header + separator
  end

  -- Apply highlighting to JSON cells in data rows
  M._highlight_json_cells(bufnr, ns_id, lines, json_columns, data_start_line, #lines - 1)
end

---Apply JSON highlighting for multiple result sets
---@param bufnr number Buffer number
---@param ns_id number Namespace ID
---@param lines string[] Buffer lines
---@param json_columns_array table<number, table<number, boolean>> Array of JSON column maps
---@param config table Plugin configuration
function M._apply_json_highlighting_multiple(bufnr, ns_id, lines, json_columns_array, config)
  -- Find all "Result Set X/Y" headers to determine table boundaries
  local result_set_indices = {}
  for line_num = 0, #lines - 1 do
    local line = lines[line_num + 1]
    if line and line:match("^Result Set %d+/%d+") then
      table.insert(result_set_indices, line_num)
    end
  end

  -- For each result set, find its table and apply JSON highlighting
  for i, json_columns in ipairs(json_columns_array) do
    local result_set_line = result_set_indices[i]
    if result_set_line then
      -- Find the table separator line (starts with | -)
      local separator_line = nil
      for line_num = result_set_line + 1, #lines - 1 do
        local line = lines[line_num + 1]
        if line and line:match("^| %-") then
          separator_line = line_num
          break
        end
      end

      if separator_line then
        -- Data starts after separator
        local data_start = separator_line + 1

        -- Data ends at next "Result Set" header or end of buffer
        local data_end = #lines - 1
        if result_set_indices[i + 1] then
          data_end = result_set_indices[i + 1] - 1
        end

        -- Apply highlighting to this result set's table
        M._highlight_json_cells(bufnr, ns_id, lines, json_columns, data_start, data_end)
      end
    end
  end
end

---Helper function to highlight JSON cells in a range of lines
---@param bufnr number Buffer number
---@param ns_id number Namespace ID
---@param lines string[] Buffer lines
---@param json_columns table<number, boolean> Map of column_index -> is_json_column
---@param start_line number Start line (0-indexed)
---@param end_line number End line (0-indexed)
function M._highlight_json_cells(bufnr, ns_id, lines, json_columns, start_line, end_line)
  for line_num = start_line, end_line do
    local line = lines[line_num + 1]  -- Lua is 1-indexed, nvim is 0-indexed
    if line and line:match("|") and not line:match("^| %-") then  -- Skip separator lines
      -- Split line by pipes to get cells
      local cells = {}
      local cell_positions = {}
      local current_pos = 1

      -- Find all pipe positions and extract cells
      for cell in line:gmatch("([^|]+)") do
        local pipe_pos = line:find("|", current_pos, true)
        if pipe_pos then
          table.insert(cells, cell)
          table.insert(cell_positions, { start = current_pos, finish = pipe_pos - 1 })
          current_pos = pipe_pos + 1
        end
      end

      -- Add the last cell after the final pipe (if any)
      if current_pos <= #line then
        local last_cell = line:sub(current_pos)
        table.insert(cells, last_cell)
        -- Find the trailing pipe position (if exists) to exclude it from highlighting
        local trailing_pipe_pos = line:find("|%s*$")
        local cell_end = trailing_pipe_pos and (trailing_pipe_pos - 1) or #line
        table.insert(cell_positions, { start = current_pos, finish = cell_end })
      end

      -- Apply highlighting to JSON columns
      -- cells[1] is empty (before first pipe), so data columns start at cells[2]
      for col_idx, cell in ipairs(cells) do
        local data_col_idx = col_idx - 1  -- Adjust for leading empty cell
        if data_col_idx > 0 and json_columns[data_col_idx] and cell_positions[col_idx] then
          local pos = cell_positions[col_idx]
          vim.api.nvim_buf_add_highlight(
            bufnr,
            ns_id,
            'EnhanceJsonCell',
            line_num,
            pos.start - 1,  -- 0-indexed
            pos.finish      -- 0-indexed, exclusive end
          )
        end
      end
    end
  end
end

---Apply highlighting to "Result Set X/Y" headers
---@param bufnr number Buffer number
---@param config table Plugin configuration
function M.apply_result_set_highlighting(bufnr, config)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Create namespace for result set header highlights
  local ns_id = vim.api.nvim_create_namespace('enhance_result_set_headers')

  -- Get all lines in buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Find and highlight "Result Set X/Y" lines
  for line_num = 0, #lines - 1 do
    local line = lines[line_num + 1]  -- Lua is 1-indexed
    if line and line:match("^Result Set") then
      -- Pattern: "Result Set X/Y" with optional "| Rows: N"
      -- We want: "Result Set " (blue) + "X/Y" (green) + " | Rows:" (blue) + " N" (green)

      -- Find "Result Set " and the X/Y part
      local result_set_end = line:find(" ", 11)  -- Find space after "Result Set"
      if not result_set_end then
        result_set_end = 11  -- "Result Set " is 11 chars
      end

      -- Highlight "Result Set " (label)
      vim.api.nvim_buf_add_highlight(
        bufnr,
        ns_id,
        'EnhanceStatusLabel',
        line_num,
        0,
        result_set_end
      )

      -- Find first pipe position to know where X/Y ends
      local first_pipe_pos = line:find("|")

      if first_pipe_pos then
        -- Highlight "X/Y " part (value) - from after "Result Set " to before first pipe
        vim.api.nvim_buf_add_highlight(
          bufnr,
          ns_id,
          'EnhanceStatusValue',
          line_num,
          result_set_end,
          first_pipe_pos - 1
        )

        -- Pattern: "Result Set X/Y | Rows: N | XX.XXms" or "Result Set X/Y | Rows: N" or "Result Set X/Y | XX.XXms"
        -- We need to handle Rows (if present) and elapsed time (if present)
        -- Order: Rows BEFORE elapsed time

        -- Find "Rows:" label (if present)
        local rows_start = line:find("Rows:", first_pipe_pos)

        if rows_start then
          -- Check if there's elapsed time after "Rows:"
          local second_pipe_pos = line:find("|", rows_start)

          if second_pipe_pos then
            -- Pattern: "Result Set X/Y | Rows: N | XX.XXms"
            -- Highlight "| Rows:" (label)
            vim.api.nvim_buf_add_highlight(
              bufnr,
              ns_id,
              'EnhanceStatusLabel',
              line_num,
              first_pipe_pos - 1,
              rows_start + 4  -- "Rows:" is 5 chars, so +4 from start
            )

            -- Highlight row count value (N)
            vim.api.nvim_buf_add_highlight(
              bufnr,
              ns_id,
              'EnhanceStatusValue',
              line_num,
              rows_start + 5,  -- After "Rows:"
              second_pipe_pos - 1
            )

            -- Highlight " | " before elapsed time (label)
            -- second_pipe_pos is 1-indexed from line:find(), so convert to 0-indexed
            vim.api.nvim_buf_add_highlight(
              bufnr,
              ns_id,
              'EnhanceStatusLabel',
              line_num,
              second_pipe_pos - 2,  -- Start of " | " (space before pipe)
              second_pipe_pos + 1   -- End after " | " (exclusive)
            )

            -- Highlight elapsed time value (XX.XXms)
            vim.api.nvim_buf_add_highlight(
              bufnr,
              ns_id,
              'EnhanceStatusValue',
              line_num,
              second_pipe_pos + 1,  -- Start after " | "
              #line
            )
          else
            -- Pattern: "Result Set X/Y | Rows: N" (no elapsed time)
            -- Highlight "| Rows:" part (label)
            vim.api.nvim_buf_add_highlight(
              bufnr,
              ns_id,
              'EnhanceStatusLabel',
              line_num,
              first_pipe_pos - 1,
              rows_start + 4  -- "Rows:" is 5 chars, so +4 from start
            )

            -- Highlight the number part (value) - everything after "Rows:"
            vim.api.nvim_buf_add_highlight(
              bufnr,
              ns_id,
              'EnhanceStatusValue',
              line_num,
              rows_start + 5,  -- After "Rows:"
              #line
            )
          end
        else
          -- Pattern: "Result Set X/Y | XX.XXms" (elapsed time only, no Rows)
          -- Highlight "| " (label)
          vim.api.nvim_buf_add_highlight(
            bufnr,
            ns_id,
            'EnhanceStatusLabel',
            line_num,
            first_pipe_pos - 1,
            first_pipe_pos + 1  -- "| "
          )

          -- Highlight elapsed time value (XX.XXms)
          vim.api.nvim_buf_add_highlight(
            bufnr,
            ns_id,
            'EnhanceStatusValue',
            line_num,
            first_pipe_pos + 1,
            #line
          )
        end
      else
        -- No pipe, highlight X/Y part as value
        vim.api.nvim_buf_add_highlight(
          bufnr,
          ns_id,
          'EnhanceStatusValue',
          line_num,
          result_set_end,
          #line
        )
      end
    end
  end
end

-- Expose for testing
M._setup_keymaps = M.setup_keymaps
M._apply_null_highlighting = M.apply_null_highlighting
M._apply_json_highlighting = M.apply_json_highlighting
M._apply_result_set_highlighting = M.apply_result_set_highlighting

return M

