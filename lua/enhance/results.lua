-- enhance.nvim - Results display
-- Handles displaying query results in buffers

local M = {}

---Generate status line from metadata
---@param metadata table Execution metadata
---@return string[] Status line (2 lines: info, separator)
local function generate_status_line(metadata)
  local info = string.format(
    "Rows: %s | %.2fms | %s | %s | %s",
    metadata.row_count and tostring(metadata.row_count) or "N/A",
    metadata.execution_time,
    metadata.connection_name,
    metadata.db_type,
    metadata.timestamp
  )

  -- Make separator match the length of the info line
  local separator = string.rep("─", #info)

  return { info, separator }
end

---Apply highlight to status line in buffer
---@param bufnr number Buffer number
---@param config table Plugin configuration
---@param position string Status line position ('top' or 'bottom')
local function apply_status_line_highlight(bufnr, config, position)
  -- Create namespace for status line highlights
  local ns_id = vim.api.nvim_create_namespace('enhance_status_line')

  -- Determine which lines to highlight based on position
  local start_line, end_line
  if position == 'top' then
    start_line = 0  -- First line (0-indexed)
    end_line = 1    -- Second line (0-indexed, exclusive)
  else  -- bottom
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    start_line = line_count - 2
    end_line = line_count - 1
  end

  -- Apply highlight to both status line rows
  for line = start_line, end_line do
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, config.status_line.highlight, line, 0, -1)
  end
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
  if metadata and config.status_line.enabled and config.status_line.position ~= 'none' then
    local status_lines = generate_status_line(metadata)

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

  -- Set keymaps
  M.setup_keymaps(buf)

  -- Apply status line highlight if metadata is provided
  if metadata and config.status_line.enabled and config.status_line.position ~= 'none' then
    apply_status_line_highlight(buf, config, config.status_line.position)
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

-- Expose for testing
M._setup_keymaps = M.setup_keymaps

return M

