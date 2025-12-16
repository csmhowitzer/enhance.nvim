-- enhance.nvim - Query buffer management
-- Handles SQL query buffers and execution

local M = {}

---Find existing query buffer by name
---@param buf_name string Buffer name to search for
---@return integer|nil bufnr Buffer number if found, nil otherwise
local function find_buffer_by_name(buf_name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name == buf_name then
        return buf
      end
    end
  end
  return nil
end

---Create a new query buffer for a connection (or reuse existing one)
---@param connection table Database connection
---@return integer bufnr Buffer number
function M.create_query_buffer(connection)
  local buf_name = string.format("[enhance] %s", connection.name)

  -- Check if buffer already exists
  local existing_buf = find_buffer_by_name(buf_name)
  if existing_buf then
    -- Buffer exists, find or create window for it
    -- Move to rightmost window (away from explorer)
    vim.cmd('wincmd l')

    -- If we're still in the explorer, create a vsplit
    local current_buf = vim.api.nvim_get_current_buf()
    if vim.bo[current_buf].filetype == 'enhance-explorer' then
      vim.cmd('vsplit')
    end

    vim.api.nvim_win_set_buf(0, existing_buf)
    vim.notify("Switched to existing query buffer", vim.log.levels.INFO)
    return existing_buf
  end

  -- Create new buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = 'sql'
  vim.bo[buf].buftype = 'nofile'

  -- Store connection info in buffer variable
  vim.b[buf].enhance_connection = connection

  -- Set buffer name
  local ok, err = pcall(vim.api.nvim_buf_set_name, buf, buf_name)
  if not ok then
    vim.notify("Failed to set buffer name: " .. tostring(err), vim.log.levels.ERROR)
    return buf
  end

  -- Set keymaps
  M.setup_keymaps(buf)

  -- Open in right side (vsplit from explorer)
  -- Move to rightmost window first
  vim.cmd('wincmd l')

  -- If we're still in the explorer, create a vsplit
  local current_buf = vim.api.nvim_get_current_buf()
  if vim.bo[current_buf].filetype == 'enhance-explorer' then
    vim.cmd('vsplit')
  end

  vim.api.nvim_win_set_buf(0, buf)
  
  -- Add helpful header comment
  local header = {
    "-- Query buffer for: " .. connection.name,
    "-- Press <F5> to execute query",
    "-- Press :w to save query (TODO)",
    "",
    "", -- Empty line for cursor positioning
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, header)

  -- Move cursor to last line (empty line after header)
  vim.api.nvim_win_set_cursor(0, {#header, 0})
  
  return buf
end

---Setup keymaps for query buffer
---@param bufnr integer Buffer number
function M.setup_keymaps(bufnr)
  local config = require("enhance").get_config()

  -- Execute query keymap
  vim.keymap.set('n', config.keymaps.execute_query, function()
    M.execute_current_query(bufnr)
  end, { buffer = bufnr, desc = "Execute SQL query" })

  -- Visual mode execution
  vim.keymap.set('v', config.keymaps.execute_query, function()
    M.execute_visual_selection(bufnr)
  end, { buffer = bufnr, desc = "Execute selected SQL" })

  -- Delete current file keymap
  vim.keymap.set('n', '<leader>dd', function()
    require("enhance.explorer").delete_file()
  end, { buffer = bufnr, desc = "Delete current file" })
end

---Execute the entire buffer content
---@param bufnr integer Buffer number
function M.execute_current_query(bufnr)
  local connection = vim.b[bufnr].enhance_connection

  if not connection then
    -- Show notification and helpful message in results window
    vim.notify("No database connection established", vim.log.levels.WARN)
    local results = require("enhance.results")
    results.display_message({
      "No database connection established",
      "",
      "To execute queries, you need to:",
      "1. Open the explorer with <leader>de",
      "2. Press <CR> on a connection to test/connect",
      "3. Click 'New Query' or use <leader>dq",
      "",
      "Or click a table sub-item (List, Columns, etc.) to auto-execute a query.",
    })
    return
  end

  -- Get all buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local query = table.concat(lines, "\n")

  -- Remove comment lines
  query = query:gsub("%-%-[^\n]*\n", "")
  query = vim.trim(query)

  if query == "" then
    vim.notify("No query to execute", vim.log.levels.WARN)
    return
  end

  -- Execute query (pass buffer number for result association)
  require("enhance.executor").execute(connection, query, bufnr)
end

---Execute visual selection
---@param bufnr integer Buffer number
function M.execute_visual_selection(bufnr)
  local connection = vim.b[bufnr].enhance_connection
  if not connection then
    -- Show notification and helpful message in results window
    vim.notify("No database connection established", vim.log.levels.WARN)
    local results = require("enhance.results")
    results.display_message({
      "No database connection established",
      "",
      "To execute queries, you need to:",
      "1. Open the explorer with <leader>de",
      "2. Press <CR> on a connection to test/connect",
      "3. Click 'New Query' or use <leader>dq",
      "",
      "Or click a table sub-item (List, Columns, etc.) to auto-execute a query.",
    })
    return
  end

  -- Get visual selection
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_pos[2] - 1, end_pos[2], false)

  local query = table.concat(lines, "\n")
  query = vim.trim(query)

  if query == "" then
    vim.notify("No query to execute", vim.log.levels.WARN)
    return
  end

  -- Execute query (pass buffer number for result association)
  require("enhance.executor").execute(connection, query, bufnr)
end

-- Expose for testing
M._setup_keymaps = M.setup_keymaps

return M

