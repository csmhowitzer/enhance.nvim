-- enhance.nvim - Results display
-- Handles displaying query results in buffers

local M = {}

---Display query results in a buffer
---@param lines string[] Result lines
---@param connection table Database connection
---@param query_bufnr number? Query buffer number (optional, for associating results)
function M.display(lines, connection, query_bufnr)
  local explorer = require("enhance.explorer")
  local timestamp = os.date("%H:%M:%S")

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

