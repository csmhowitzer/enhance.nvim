-- enhance.nvim - Connection Explorer
-- Tree-based database connection browser with drawer UI

local M = {}

---@type number? Window ID for explorer drawer
local explorer_win = nil

---@type number? Buffer ID for explorer
local explorer_buf = nil

---@type number? Tab number where enhance workspace is active
local explorer_tab = nil

---@type number? Window ID for query editor
local query_editor_win = nil

---@type number? Window ID for results display
local results_win = nil

---@type table? Currently active database connection
local active_connection = nil

---@type boolean Whether enhance workspace has been initialized
local workspace_initialized = false

---@type table<string, boolean> Expanded state for tree nodes
local expanded = {}

---@type table<string, string[]> Cached table lists per connection
local table_cache = {}

---@type table<string, table[]> Tracked buffers per connection
-- Format: { ["example.db"] = { {bufnr=5, filepath="/path/to/file.sql"}, ... } }
local connection_buffers = {}

---@type integer? Last results buffer number
local last_results_buf = nil

---Get connection-specific tmp directory
---@param connection table Database connection
---@return string? tmp_dir Path to tmp directory, or nil on error
local function get_connection_tmp_dir(connection)
  local base = vim.fn.stdpath('data') .. '/enhance.nvim'
  local conn_dir = base .. '/' .. connection.name .. '/tmp'

  local ok, err = pcall(vim.fn.mkdir, conn_dir, 'p')
  if not ok then
    vim.notify(
      string.format("Failed to create tmp directory: %s\nError: %s", conn_dir, err),
      vim.log.levels.ERROR
    )
    return nil
  end

  return conn_dir
end

---Get connection-specific queries directory
---@param connection table Database connection
---@return string? queries_dir Path to queries directory, or nil on error
local function get_connection_queries_dir(connection)
  local base = vim.fn.stdpath('data') .. '/enhance.nvim'
  local conn_dir = base .. '/' .. connection.name .. '/queries'

  local ok, err = pcall(vim.fn.mkdir, conn_dir, 'p')
  if not ok then
    vim.notify(
      string.format("Failed to create queries directory: %s\nError: %s", conn_dir, err),
      vim.log.levels.ERROR
    )
    return nil
  end

  return conn_dir
end

---Check if filepath is in tmp directory
---@param filepath string Full path to file
---@return boolean is_tmp True if file is in tmp directory
local function is_tmp_file(filepath)
  return filepath:match('/tmp/[^/]+%.sql$') ~= nil
end

---Extract connection name from tmp filepath
---@param filepath string Full path to tmp file
---@return string? conn_name Connection name or nil
local function get_connection_from_tmp_path(filepath)
  local match = filepath:match('/enhance%.nvim/([^/]+)/tmp/')
  return match
end

---Add buffer to tracking for a connection
---@param conn_name string Connection name
---@param bufnr number Buffer number
---@param filepath string Full path to buffer file
local function add_buffer_to_tracking(conn_name, bufnr, filepath)
  if not connection_buffers[conn_name] then
    connection_buffers[conn_name] = {}
  end

  -- Check if already tracked
  for _, buf_info in ipairs(connection_buffers[conn_name]) do
    if buf_info.bufnr == bufnr then
      return -- Already tracked
    end
  end

  table.insert(connection_buffers[conn_name], {
    bufnr = bufnr,
    filepath = filepath,
    result_bufnr = nil,      -- Associated result buffer (if any)
    result_timestamp = nil,  -- Timestamp of last execution (for display)
  })
end

---Associate result buffer with query buffer
---@param query_bufnr number Query buffer number
---@param result_bufnr number Result buffer number
---@param timestamp string Timestamp of execution (HH:MM:SS)
local function associate_result_buffer(query_bufnr, result_bufnr, timestamp)
  -- First try to find existing tracking entry
  for _, buffers in pairs(connection_buffers) do
    for _, buf_info in ipairs(buffers) do
      if buf_info.bufnr == query_bufnr then
        buf_info.result_bufnr = result_bufnr
        buf_info.result_timestamp = timestamp
        return
      end
    end
  end

  -- If not found, add to tracking (buffer might have been opened before tracking was added)
  -- Get buffer's connection and filepath
  local buf_conn = vim.b[query_bufnr].enhance_connection
  if buf_conn then
    local filepath = vim.api.nvim_buf_get_name(query_bufnr)
    if filepath and filepath ~= "" then
      add_buffer_to_tracking(buf_conn.name, query_bufnr, filepath)
      -- Now associate the result
      if connection_buffers[buf_conn.name] then
        for _, buf_info in ipairs(connection_buffers[buf_conn.name]) do
          if buf_info.bufnr == query_bufnr then
            buf_info.result_bufnr = result_bufnr
            buf_info.result_timestamp = timestamp
            return
          end
        end
      end
    end
  end
end

---Get result buffer info for a query buffer
---@param query_bufnr number Query buffer number
---@return number?, string? result_bufnr, timestamp
local function get_result_buffer_info(query_bufnr)
  for _, buffers in pairs(connection_buffers) do
    for _, buf_info in ipairs(buffers) do
      if buf_info.bufnr == query_bufnr then
        return buf_info.result_bufnr, buf_info.result_timestamp
      end
    end
  end
  return nil, nil
end

---Remove buffer from tracking (also deletes associated result buffer)
---@param bufnr number Buffer number to remove
local function remove_buffer_from_tracking(bufnr)
  for conn_name, buffers in pairs(connection_buffers) do
    for i, buf_info in ipairs(buffers) do
      if buf_info.bufnr == bufnr then
        -- Delete associated result buffer if it exists
        if buf_info.result_bufnr and vim.api.nvim_buf_is_valid(buf_info.result_bufnr) then
          vim.api.nvim_buf_delete(buf_info.result_bufnr, { force = true })
        end
        table.remove(buffers, i)
        return
      end
    end
  end
end

---Clean up invalid buffers from tracking table
---Removes entries for buffers that are no longer valid
local function cleanup_invalid_buffers()
  for conn_name, buffers in pairs(connection_buffers) do
    local i = 1
    while i <= #buffers do
      local buf_info = buffers[i]
      if not vim.api.nvim_buf_is_valid(buf_info.bufnr) then
        -- Clean up associated result buffer if it exists
        if buf_info.result_bufnr and vim.api.nvim_buf_is_valid(buf_info.result_bufnr) then
          vim.api.nvim_buf_delete(buf_info.result_bufnr, { force = true })
        end
        table.remove(buffers, i)
        -- Don't increment i, check same index again
      else
        i = i + 1
      end
    end
  end
end

---Get all buffers for a connection (sorted by timestamp, newest first)
---Shows both files on disk AND tracked buffers not yet saved
---Merges with tracking data to include result buffer info
---@param conn_name string Connection name
---@return table[] buffers List of file info tables with result tracking data
local function get_buffers_for_connection(conn_name)
  local connections = require("enhance.connections")
  local conn = connections.get_connection(conn_name)
  if not conn then
    return {}
  end

  local tmp_dir = get_connection_tmp_dir(conn)
  local files = vim.fn.glob(tmp_dir .. '/*.sql', false, true)

  -- Start with files on disk
  local buffers = {}
  local seen_paths = {}

  for _, filepath in ipairs(files) do
    seen_paths[filepath] = true
    local bufnr = vim.fn.bufnr(filepath)

    -- Look up tracking data
    local result_bufnr, result_timestamp
    if bufnr ~= -1 then
      result_bufnr, result_timestamp = get_result_buffer_info(bufnr)
    else
      if connection_buffers[conn_name] then
        for _, tracked_buf in ipairs(connection_buffers[conn_name]) do
          if tracked_buf.filepath == filepath then
            result_bufnr = tracked_buf.result_bufnr
            result_timestamp = tracked_buf.result_timestamp
            break
          end
        end
      end
    end

    table.insert(buffers, {
      bufnr = bufnr,
      filepath = filepath,
      result_bufnr = result_bufnr,
      result_timestamp = result_timestamp,
    })
  end

  -- Add tracked buffers that aren't on disk yet (new unsaved queries)
  if connection_buffers[conn_name] then
    for _, tracked_buf in ipairs(connection_buffers[conn_name]) do
      if not seen_paths[tracked_buf.filepath] and vim.api.nvim_buf_is_valid(tracked_buf.bufnr) then
        table.insert(buffers, {
          bufnr = tracked_buf.bufnr,
          filepath = tracked_buf.filepath,
          result_bufnr = tracked_buf.result_bufnr,
          result_timestamp = tracked_buf.result_timestamp,
        })
      end
    end
  end

  -- Sort by file modification time (newest first), with unsaved buffers at top
  table.sort(buffers, function(a, b)
    local time_a = vim.fn.getftime(a.filepath)
    local time_b = vim.fn.getftime(b.filepath)
    -- Files that don't exist yet (time = -1) should appear first
    if time_a == -1 and time_b ~= -1 then return true end
    if time_a ~= -1 and time_b == -1 then return false end
    return time_a > time_b
  end)

  return buffers
end

---Extract display name from filepath
---@param filepath string Full path to file
---@return string display_name Filename without path and extension
local function get_buffer_display_name(filepath)
  local filename = vim.fn.fnamemodify(filepath, ':t')  -- Get filename only
  return filename:gsub('%.sql$', '')  -- Remove .sql extension
end

---Get all saved queries for a connection (sorted alphabetically)
---Scans queries directory to show ALL saved query files
---@param conn_name string Connection name
---@return table[] queries List of file info tables
local function get_saved_queries_for_connection(conn_name)
  local connections = require("enhance.connections")
  local conn = connections.get_connection(conn_name)
  if not conn then
    return {}
  end

  local queries_dir = get_connection_queries_dir(conn)
  local files = vim.fn.glob(queries_dir .. '/*.sql', false, true)

  local queries = {}
  for _, filepath in ipairs(files) do
    -- Get buffer number if file is open, otherwise use -1
    local bufnr = vim.fn.bufnr(filepath)
    table.insert(queries, {
      bufnr = bufnr,
      filepath = filepath,
    })
  end

  -- Sort alphabetically by filename
  table.sort(queries, function(a, b)
    local name_a = vim.fn.fnamemodify(a.filepath, ':t')
    local name_b = vim.fn.fnamemodify(b.filepath, ':t')
    return name_a < name_b
  end)

  return queries
end

---Detect Nerd Font support
---@return boolean
local function has_nerd_font()
  if vim.g.have_nerd_font ~= nil then
    return vim.g.have_nerd_font
  end
  
  -- Test if Nerd Font characters render as single-width
  local test_chars = { "󰆼", "󰘦", "󰢱" }
  for _, char in ipairs(test_chars) do
    if vim.fn.strdisplaywidth(char) == 1 then
      vim.g.have_nerd_font = true
      return true
    end
  end
  
  vim.g.have_nerd_font = false
  return false
end

---Fetch table names from database
---@param connection table Database connection
---@param force_refresh boolean? Force refresh (skip cache)
---@return string[] tables List of table names
local function fetch_tables(connection, force_refresh)
  local cache_key = "tables:" .. connection.name

  -- Return cached if available (unless force_refresh is true)
  if not force_refresh and table_cache[cache_key] then
    return table_cache[cache_key]
  end

  local tables = {}
  local db_type = connection.type:lower():gsub("[%s%-_]", "")

  if db_type == "sqlite" then
    -- SQLite: Query sqlite_master
    local db_path = vim.fn.expand(connection.path)
    local output = vim.fn.system({
      'sqlite3',
      db_path,
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
    })

    if vim.v.shell_error == 0 then
      for line in output:gmatch("[^\r\n]+") do
        if line ~= "" then
          table.insert(tables, line)
        end
      end
    end
  elseif db_type == "sqlserver" or db_type == "mssql" then
    -- SQL Server: Query INFORMATION_SCHEMA
    local cmd = {
      'sqlcmd',
      '-S', connection.server or connection.host,
      '-d', connection.database,
      '-h', '-1', -- Remove headers
      '-W', -- Remove trailing spaces
    }

    if connection.user or connection.username then
      table.insert(cmd, '-U')
      table.insert(cmd, connection.user or connection.username)
      if connection.password then
        table.insert(cmd, '-P')
        table.insert(cmd, connection.password)
      end
    else
      table.insert(cmd, '-E') -- Windows authentication
    end

    -- Trust server certificate (for self-signed certs)
    if connection.trust_server_certificate ~= false then
      table.insert(cmd, '-C')
    end

    table.insert(cmd, '-Q')
    table.insert(cmd, "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;")

    local output = vim.fn.system(cmd)

    if vim.v.shell_error == 0 then
      for line in output:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
          table.insert(tables, trimmed)
        end
      end
    end

  elseif db_type == "mysql" or db_type == "mariadb" then
    -- MySQL: SHOW TABLES
    local cmd = {
      'mysql',
      '-h', connection.host or 'localhost',
      '-D', connection.database,
      '-N', -- No column names
      '-s', -- Silent mode
    }

    if connection.user then
      table.insert(cmd, '-u')
      table.insert(cmd, connection.user)
    end

    if connection.password then
      table.insert(cmd, '-p' .. connection.password)
    end

    table.insert(cmd, '-e')
    table.insert(cmd, 'SHOW TABLES;')

    local output = vim.fn.system(cmd)

    if vim.v.shell_error == 0 then
      for line in output:gmatch("[^\r\n]+") do
        if line ~= "" then
          table.insert(tables, line)
        end
      end
    end

  elseif db_type == "postgres" or db_type == "postgresql" then
    -- PostgreSQL: Query pg_tables
    local cmd = {
      'psql',
      '-h', connection.host or 'localhost',
      '-d', connection.database,
      '-t', -- Tuples only (no headers)
      '-A', -- Unaligned output
    }

    if connection.user then
      table.insert(cmd, '-U')
      table.insert(cmd, connection.user)
    end

    table.insert(cmd, '-c')
    table.insert(cmd, "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;")

    local output = vim.fn.system(cmd)

    if vim.v.shell_error == 0 then
      for line in output:gmatch("[^\r\n]+") do
        if line ~= "" then
          table.insert(tables, line)
        end
      end
    end
  end

  -- Cache the result
  table_cache[cache_key] = tables
  return tables
end

---Get icon for database type
---@param db_type string Database type (sqlite, sqlserver, mysql, postgres)
---@return string icon Icon character
local function get_db_icon(db_type)
  if has_nerd_font() then
    -- Normalize type names
    local normalized = db_type:lower():gsub("[%s%-_]", "")

    if normalized == "sqlite" then
      return "󰆼" -- nf-md-database (SQLite)
    elseif normalized == "sqlserver" or normalized == "mssql" or normalized == "tsql" then
      return "󰘐" -- nf-md-microsoft (SQL Server)
    elseif normalized == "mysql" or normalized == "mariadb" then
      return "" -- nf-dev-mysql
    elseif normalized == "postgres" or normalized == "postgresql" then
      return "󰆼" -- nf-md-database (same as SQLite)
    else
      return "󰆼" -- default database icon
    end
  else
    -- Unicode fallbacks
    if db_type:lower():match("sqlite") then
      return "🗄️"
    elseif db_type:lower():match("sql") or db_type:lower():match("mssql") then
      return "🔷" -- SQL Server
    elseif db_type:lower():match("mysql") then
      return "🐬" -- MySQL (dolphin)
    elseif db_type:lower():match("postgres") then
      return "🗄️" -- PostgreSQL (same as SQLite)
    else
      return "🗄️"
    end
  end
end

---Get expand/collapse arrow icon
---@param is_expanded boolean Whether node is expanded
---@return string arrow Arrow character
local function get_arrow_icon(is_expanded)
  return is_expanded and "▾" or "▸"
end

---Get icon for tree node type
---@param node_type string Node type (connection, tables, saved, table, new_query, table_subitem, buffer, saved_query, result)
---@return string icon Icon character
local function get_node_icon(node_type)
  if node_type == "tables" then
    return "󰓱" -- vim-dadbod-ui tables folder icon
  elseif node_type == "saved" then
    return "" -- vim-dadbod-ui saved queries folder icon (folder, not disk)
  elseif node_type == "table" then
    return "󰓫" -- vim-dadbod-ui table icon
  elseif node_type == "new_query" then
    return "󰓰" -- vim-dadbod-ui new query icon
  elseif node_type == "table_subitem" then
    return "󰓫" -- reuse table icon for sub-items
  elseif node_type == "buffer" then
    return "" -- vim-dadbod-ui buffers folder icon
  elseif node_type == "buffer_item" then
    return "" -- vim-dadbod-ui individual buffer icon
  elseif node_type == "saved_query" then
    return "" -- vim-dadbod-ui saved query icon
  elseif node_type == "result" then
    return "󰋼" -- result/chart icon for query results
  end
  return ""
end

---Build explorer content lines
---@return string[] lines Content lines for explorer buffer
local function build_explorer_content()
  local lines = {}
  local connections = require("enhance.connections").get_connections()
  local current = require("enhance.connections").get_current()

  -- Header
  table.insert(lines, "Database Explorer")
  table.insert(lines, "")

  -- Connections tree
  for _, conn in ipairs(connections) do
    local is_current = current and current.name == conn.name
    -- Show connection status with checkmark/X
    local status_icon = is_current and "✓" or "✗"
    local icon = get_db_icon(conn.type)
    local conn_key = "conn:" .. conn.name
    local is_expanded = expanded[conn_key]

    -- Use arrow icons for expand/collapse (consistent with folders)
    local expand_icon = is_expanded and "▾" or "▸"

    -- Connection line: status, expand arrow, db icon, name
    local line = string.format("%s %s %s %s", status_icon, expand_icon, icon, conn.name)
    table.insert(lines, line)

    -- Expanded content
    if is_expanded then

      -- New Query option
      local new_query_icon = get_node_icon("new_query")
      table.insert(lines, string.format("    %s  New Query", new_query_icon))

      -- Buffers section with count
      local buffers = get_buffers_for_connection(conn.name)
      local buffers_key = conn_key .. ":buffers"
      local buffers_expanded = expanded[buffers_key]
      local buffers_arrow = get_arrow_icon(buffers_expanded)
      local buffer_icon = get_node_icon("buffer")
      table.insert(lines, string.format("    %s %s Buffers (%d)", buffers_arrow, buffer_icon, #buffers))

      -- Show buffer list if expanded
      if buffers_expanded then
        for _, buf_info in ipairs(buffers) do
          local display_name = get_buffer_display_name(buf_info.filepath)
          local item_buffer_icon = get_node_icon("buffer_item")

          -- Check if this buffer has associated results (data already merged from get_buffers_for_connection)
          local has_results = buf_info.result_bufnr and vim.api.nvim_buf_is_valid(buf_info.result_bufnr)

          -- Make buffer expandable if it has results
          if has_results then
            local buffer_key = conn_key .. ":buffer:" .. display_name
            local buffer_expanded = expanded[buffer_key]
            local buffer_arrow = get_arrow_icon(buffer_expanded)
            table.insert(lines, string.format("      %s %s  %s", buffer_arrow, item_buffer_icon, display_name))

            -- Show results child item if buffer is expanded
            if buffer_expanded then
              local result_icon = get_node_icon("result")
              table.insert(lines, string.format("        %s  Results (%s)", result_icon, buf_info.result_timestamp))
            end
          else
            -- No results - just show buffer without arrow
            table.insert(lines, string.format("        %s  %s", item_buffer_icon, display_name))
          end
        end
      end

      -- Saved queries folder with count (BEFORE Tables - vim-dadbod-ui order)
      local saved_key = conn_key .. ":saved"
      local saved_expanded = expanded[saved_key]
      local saved_arrow = get_arrow_icon(saved_expanded)
      local saved_icon = get_node_icon("saved")
      local saved_queries = get_saved_queries_for_connection(conn.name)
      table.insert(lines, string.format("    %s %s  Saved Queries (%d)", saved_arrow, saved_icon, #saved_queries))

      -- Show saved query list if expanded
      if saved_expanded then
        for _, query_info in ipairs(saved_queries) do
          local display_name = get_buffer_display_name(query_info.filepath)
          local saved_query_icon = get_node_icon("saved_query")
          table.insert(lines, string.format("      %s  %s", saved_query_icon, display_name))
        end
      end

      -- Tables folder with count
      local tables_key = conn_key .. ":tables"
      local tables_expanded = expanded[tables_key]
      local tables_arrow = get_arrow_icon(tables_expanded)
      local tables_icon = get_node_icon("tables")
      local tables = fetch_tables(conn)
      local tables_count = #tables
      table.insert(lines, string.format("    %s %s  Tables (%d)", tables_arrow, tables_icon, tables_count))

      -- Show table list if expanded
      if tables_expanded then
        local table_icon = get_node_icon("table")
        for _, table_name in ipairs(tables) do
          -- Table name with expand/collapse icon
          local table_key = conn_key .. ":table:" .. table_name
          local table_expanded = expanded[table_key]
          local table_arrow = get_arrow_icon(table_expanded)

          table.insert(lines, string.format("      %s %s  %s", table_arrow, table_icon, table_name))

          -- Show table sub-items if expanded
          if table_expanded then
            local subitem_icon = get_node_icon("table_subitem")
            table.insert(lines, string.format("          %s  Columns", subitem_icon))
            table.insert(lines, string.format("          %s  List (200 rows)", subitem_icon))
            table.insert(lines, string.format("          %s  Primary Keys", subitem_icon))
            table.insert(lines, string.format("          %s  Foreign Keys", subitem_icon))
            table.insert(lines, string.format("          %s  Indexes", subitem_icon))
            table.insert(lines, string.format("          %s  CREATE Table", subitem_icon))
            table.insert(lines, string.format("          %s  UPDATE Template", subitem_icon))
            table.insert(lines, string.format("          %s  DROP Table", subitem_icon))
            table.insert(lines, string.format("          %s  DELETE Records", subitem_icon))
          end
        end
      end
    end
  end
  
  table.insert(lines, "")
  table.insert(lines, "Press <CR> to expand/select, q to close")
  
  return lines
end

---Apply syntax highlighting to connection status icons and counts
---@private
local function apply_status_highlights()
  if not explorer_buf or not vim.api.nvim_buf_is_valid(explorer_buf) then
    return
  end

  local ns_id = vim.api.nvim_create_namespace("enhance-connection-status")
  vim.api.nvim_buf_clear_namespace(explorer_buf, ns_id, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(explorer_buf, 0, -1, false)

  for line_num, line in ipairs(lines) do
    -- Check for connection status icons at start of line
    if line:match("^✓") then
      -- Green checkmark for connected
      vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceConnected", line_num - 1, 0, 1)
    elseif line:match("^✗") then
      -- Red X for disconnected
      vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceDisconnected", line_num - 1, 0, 1)
    end

    -- Highlight count indicators like "(41)" in red/orange
    local count_start, count_end = line:find("%(%d+%)")
    if count_start then
      vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceCount", line_num - 1, count_start - 1, count_end)
    end

    -- Highlight blue icons (New Query, Buffers, Saved Queries, Tables, individual items)
    -- Find icon positions using string.find for accurate byte positions
    local icon_start, icon_end

    -- New Query icon: 󰓰
    icon_start, icon_end = line:find("󰓰")
    if icon_start and line:match("New Query") then
      vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceIconBlue", line_num - 1, icon_start - 1, icon_end)
    end

    -- Buffers folder icon (blue)
    local buffers_folder_icon = get_node_icon("buffer")
    icon_start, icon_end = line:find(buffers_folder_icon, 1, true)
    if icon_start and line:match("Buffers") then
      vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceIconBlue", line_num - 1, icon_start - 1, icon_end)
    end

    -- Individual buffer icon (blue for no results, orange for has results)
    local buffer_item_icon = get_node_icon("buffer_item")
    icon_start, icon_end = line:find(buffer_item_icon, 1, true)
    if icon_start then
      -- Check if this buffer has an arrow (indicates it has results)
      local has_arrow = line:find("▸") or line:find("▾")
      if has_arrow and has_arrow < icon_start then
        -- Buffer with results - orange
        vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceIconOrange", line_num - 1, icon_start - 1, icon_end)
      else
        -- Buffer without results - blue
        vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceIconBlue", line_num - 1, icon_start - 1, icon_end)
      end
    end

    -- Saved Queries folder icon (blue)
    local saved_folder_icon = get_node_icon("saved")
    icon_start, icon_end = line:find(saved_folder_icon, 1, true)
    if icon_start and line:match("Saved Queries") then
      vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceIconBlue", line_num - 1, icon_start - 1, icon_end)
    end

    -- Individual saved query icon (blue)
    local saved_item_icon = get_node_icon("saved_query")
    icon_start, icon_end = line:find(saved_item_icon, 1, true)
    if icon_start and not line:match("Saved Queries") then
      vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceIconBlue", line_num - 1, icon_start - 1, icon_end)
    end

    -- Tables folder icon: 󰓱
    icon_start, icon_end = line:find("󰓱")
    if icon_start and line:match("Tables") then
      vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceIconBlue", line_num - 1, icon_start - 1, icon_end)
    end

    -- Individual table icon: 󰓫 (blue for tables, orange for sub-items)
    icon_start, icon_end = line:find("󰓫")
    if icon_start then
      -- Orange for table sub-items
      if line:match("Columns") or line:match("List") or line:match("Primary Keys") or
         line:match("Foreign Keys") or line:match("Indexes") or line:match("CREATE Table") or
         line:match("UPDATE Template") or line:match("DROP Table") or line:match("DELETE Records") then
        vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceIconOrange", line_num - 1, icon_start - 1, icon_end)
      else
        -- Blue for table items
        vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceIconBlue", line_num - 1, icon_start - 1, icon_end)
      end
    end

    -- Result buffer icon: 󰋼 (purple)
    icon_start, icon_end = line:find("󰋼")
    if icon_start and line:match("Results") then
      vim.api.nvim_buf_add_highlight(explorer_buf, ns_id, "EnhanceIconPurple", line_num - 1, icon_start - 1, icon_end)
    end
  end
end

---Refresh explorer buffer content
local function refresh_explorer()
  if not explorer_buf or not vim.api.nvim_buf_is_valid(explorer_buf) then
    return
  end

  -- Clean up invalid buffers from tracking table
  cleanup_invalid_buffers()

  -- Save cursor position
  local cursor_pos = nil
  if explorer_win and vim.api.nvim_win_is_valid(explorer_win) then
    cursor_pos = vim.api.nvim_win_get_cursor(explorer_win)
  end

  local lines = build_explorer_content()

  vim.bo[explorer_buf].modifiable = true
  vim.api.nvim_buf_set_lines(explorer_buf, 0, -1, false, lines)
  vim.bo[explorer_buf].modifiable = false

  -- Apply syntax highlighting to status icons
  apply_status_highlights()

  -- Force redraw to update visible content (especially when explorer isn't focused)
  vim.cmd('redraw')

  -- Restore cursor position
  if cursor_pos and explorer_win and vim.api.nvim_win_is_valid(explorer_win) then
    -- Ensure cursor is within bounds
    local max_line = #lines
    if cursor_pos[1] > max_line then
      cursor_pos[1] = max_line
    end
    vim.api.nvim_win_set_cursor(explorer_win, cursor_pos)
  end

  -- Force immediate redraw
  vim.schedule(function()
    if explorer_win and vim.api.nvim_win_is_valid(explorer_win) then
      vim.api.nvim_win_call(explorer_win, function()
        vim.cmd('redraw!')
      end)
    end
  end)
end

---Simple confirmation dialog for file deletion
---@param message string Message to display
---@param callback function Callback with boolean result
local function confirm_delete(message, callback)
  local width = 20 + #message
  local height = 3
  local bufnr = vim.api.nvim_create_buf(false, true)

  -- Calculate centered position
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Set buffer content
  local content = {
    message,
    "",
    "[Y]es   [N]o",
  }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

  -- Set buffer options
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = bufnr })
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })

  -- Create window
  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Confirm Delete ",
    title_pos = "center",
  })

  -- Set highlights
  vim.api.nvim_set_option_value(
    "winhighlight",
    "FloatBorder:EnhanceDeleteBorder,FloatTitle:EnhanceDeleteTitle",
    { win = winnr }
  )

  vim.api.nvim_set_hl(0, "EnhanceDeleteBorder", { fg = "#f9e2af", bold = true })
  vim.api.nvim_set_hl(0, "EnhanceDeleteTitle", { fg = "#f38ba8", bold = true })

  -- Handle keypress
  local close_window = function()
    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_close(winnr, true)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end

  vim.keymap.set("n", "y", function()
    close_window()
    callback(true)
  end, { buffer = bufnr, nowait = true })

  vim.keymap.set("n", "Y", function()
    close_window()
    callback(true)
  end, { buffer = bufnr, nowait = true })

  vim.keymap.set("n", "n", function()
    close_window()
    callback(false)
  end, { buffer = bufnr, nowait = true })

  vim.keymap.set("n", "N", function()
    close_window()
    callback(false)
  end, { buffer = bufnr, nowait = true })

  vim.keymap.set("n", "<Esc>", function()
    close_window()
    callback(false)
  end, { buffer = bufnr, nowait = true })
end

---Find file by name in tmp and queries directories
---@param filename string Filename to search for (without extension)
---@param conn_name string Connection name
---@return string? filepath Full path to file if found
local function find_file_by_name(filename, conn_name)
  local connections = require("enhance.connections")
  local conn = connections.get_connection(conn_name)
  if not conn then
    return nil
  end

  -- Add .sql extension if not present
  if not filename:match('%.sql$') then
    filename = filename .. '.sql'
  end

  -- Search in tmp directory
  local tmp_dir = get_connection_tmp_dir(conn)
  local tmp_files = vim.fn.glob(tmp_dir .. '/*.sql', false, true)
  for _, filepath in ipairs(tmp_files) do
    local name = vim.fn.fnamemodify(filepath, ':t')
    if name == filename then
      return filepath
    end
  end

  -- Search in queries directory
  local queries_dir = get_connection_queries_dir(conn)
  local query_files = vim.fn.glob(queries_dir .. '/*.sql', false, true)
  for _, filepath in ipairs(query_files) do
    local name = vim.fn.fnamemodify(filepath, ':t')
    if name == filename then
      return filepath
    end
  end

  return nil
end

---Delete a file and close its buffer if open
---@param filepath string Full path to file
local function delete_file_impl(filepath)
  if not filepath or filepath == "" then
    vim.notify("No file to delete", vim.log.levels.ERROR)
    return
  end

  -- Check if file exists
  if vim.fn.filereadable(filepath) ~= 1 then
    vim.notify("File not found: " .. filepath, vim.log.levels.ERROR)
    return
  end

  -- Determine if it's a tmp file or saved query
  local is_tmp = is_tmp_file(filepath)
  local filename = vim.fn.fnamemodify(filepath, ':t:r')

  -- Get buffer number if file is open
  local bufnr = vim.fn.bufnr(filepath)
  local is_current_buffer = false
  if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
    -- Check if it's the current buffer in query editor
    if query_editor_win and vim.api.nvim_win_is_valid(query_editor_win) then
      local current_buf = vim.api.nvim_win_get_buf(query_editor_win)
      is_current_buffer = (bufnr == current_buf)
    end
  end

  local do_delete = function()
    -- Save explorer visibility state
    local explorer_was_visible = explorer_win and vim.api.nvim_win_is_valid(explorer_win)

    -- Delete the file with error handling
    local ok, result = pcall(vim.fn.delete, filepath)
    if not ok then
      vim.notify(
        string.format("Failed to delete file: %s\nError: %s", filepath, result),
        vim.log.levels.ERROR
      )
      return
    end

    if result ~= 0 then
      vim.notify(
        string.format("Failed to delete file: %s\nReturn code: %d", filepath, result),
        vim.log.levels.ERROR
      )
      return
    end

    -- If it was the current buffer, create new query BEFORE deleting buffer
    -- This prevents the query editor window from closing
    if is_current_buffer then
      -- Ensure query editor window is valid and focused
      if query_editor_win and vim.api.nvim_win_is_valid(query_editor_win) then
        vim.api.nvim_set_current_win(query_editor_win)
      end

      -- Create new query buffer first (this will switch to it)
      M.new_query()

      -- Now delete the old buffer (it's no longer active in the window)
      if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end

      -- Ensure focus stays on query editor, not explorer
      if query_editor_win and vim.api.nvim_win_is_valid(query_editor_win) then
        vim.api.nvim_set_current_win(query_editor_win)
      end
    else
      -- Not the current buffer, just delete it
      if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end

    -- Refresh explorer (preserves visibility state)
    refresh_explorer()

    -- Notify user
    vim.notify("Deleted: " .. filename, vim.log.levels.INFO)
  end

  -- Tmp files: delete immediately
  -- Saved queries: show confirmation
  if is_tmp then
    do_delete()
  else
    confirm_delete("Delete saved query '" .. filename .. "'?", function(confirmed)
      if confirmed then
        do_delete()
      end
    end)
  end
end

---Handle saving a tmp buffer to queries directory
---@param bufnr number Buffer number
local function handle_tmp_buffer_save(bufnr)
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  if not is_tmp_file(filepath) then
    -- Not a tmp file, let normal save happen
    return false
  end

  -- Get connection name from path
  local conn_name = get_connection_from_tmp_path(filepath)
  if not conn_name then
    vim.notify("Could not determine connection from tmp file path", vim.log.levels.ERROR)
    return true -- Prevent save
  end

  -- Get connection object
  local connections = require("enhance.connections")
  local conn = connections.get_connection(conn_name)
  if not conn then
    vim.notify("Connection not found: " .. conn_name, vim.log.levels.ERROR)
    return true -- Prevent save
  end

  -- Extract default filename from tmp filename
  local tmp_filename = vim.fn.fnamemodify(filepath, ':t:r') -- Remove path and extension
  -- Remove timestamp prefix (YYYY-MM-DD-HHMMSS-)
  local default_name = tmp_filename:gsub('^%d%d%d%d%-%d%d%-%d%d%-%d%d%d%d%d%d%-', '')

  -- Defer the prompt to avoid focus issues
  vim.schedule(function()
    -- Prompt user for filename
    vim.ui.input({
      prompt = "Save query as: ",
      default = default_name,
    }, function(input)
      if not input or input == "" then
        vim.notify("Save cancelled", vim.log.levels.INFO)
        return
      end

      -- Ensure .sql extension
      local filename = input
      if not filename:match('%.sql$') then
        filename = filename .. '.sql'
      end

      -- Get queries directory
      local queries_dir = get_connection_queries_dir(conn)
      local new_filepath = queries_dir .. '/' .. filename

      -- Check if file already exists
      if vim.fn.filereadable(new_filepath) == 1 then
        vim.notify("File already exists: " .. filename, vim.log.levels.ERROR)
        return
      end

      -- Get buffer content
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Write to new location
      local write_ok, write_err = pcall(vim.fn.writefile, lines, new_filepath)
      if not write_ok then
        vim.notify(
          string.format("Failed to write file: %s\nError: %s", new_filepath, write_err),
          vim.log.levels.ERROR
        )
        return
      end

      -- Delete old tmp file
      local delete_ok, delete_err = pcall(vim.fn.delete, filepath)
      if not delete_ok then
        vim.notify(
          string.format("Warning: Failed to delete tmp file: %s\nError: %s", filepath, delete_err),
          vim.log.levels.WARN
        )
        -- Continue anyway since the new file was saved successfully
      end

      -- Update buffer name to new location
      pcall(vim.api.nvim_buf_set_name, bufnr, new_filepath)

      -- Mark buffer as unmodified
      vim.bo[bufnr].modified = false

      -- Refresh explorer (file is deleted, so it will disappear from list)
      refresh_explorer()

      vim.notify("Query saved: " .. filename, vim.log.levels.INFO)
    end)
  end)

  return true -- Prevent default save behavior
end

---Parse line to extract connection and node information
---@param line string Line content
---@param line_num number Line number
---@return table? info Parsed information {type, conn_name, node_type}
local function parse_line(line, line_num)
  if not line or line == "" or line_num <= 2 then
    return nil -- Header lines
  end

  -- Check indentation to determine depth
  local indent = line:match("^(%s*)")
  local indent_level = #indent

  -- Child node (indented) - CHECK THIS FIRST before connection detection
  if indent_level >= 4 then
    -- Find parent connection by looking backwards
    for i = line_num - 1, 1, -1 do
      local parent_line = vim.api.nvim_buf_get_lines(explorer_buf, i - 1, i, false)[1]
      if parent_line then
        local parent_indent = parent_line:match("^(%s*)")
        if #parent_indent < indent_level then
          local parent_info = parse_line(parent_line, i)

          if parent_info and parent_info.type == "connection" then
            -- Determine node type
            if line:match("New Query") then
              return { type = "new_query", conn_name = parent_info.conn_name }
            elseif line:match("Buffers") then
              return { type = "buffers", conn_name = parent_info.conn_name }
            elseif line:match("Tables") then
              return { type = "tables", conn_name = parent_info.conn_name }
            elseif line:match("Saved Queries") then
              return { type = "saved", conn_name = parent_info.conn_name }
            end
          elseif parent_info and parent_info.type == "buffers" then
            -- This is a buffer item under Buffers folder
            -- Extract filename from line (everything after the icon)
            local trimmed = line:match("^%s*(.-)%s*$")

            -- Check if this is a "Results (HH:MM:SS)" child item
            if trimmed:match("Results%s*%(") then
              -- This is a result item - need to find parent buffer name
              -- We'll handle this by looking up the line above
              return { type = "result_item", conn_name = parent_info.conn_name, line_num = line_num }
            end

            -- Remove arrow and icon, extract filename
            -- Use the actual buffer item icon to split the line
            local buffer_item_icon = get_node_icon("buffer_item")

            -- Remove arrow if present
            local without_arrow = trimmed:gsub("^[▸▾]%s*", "")

            -- Split on the icon and get everything after it
            local parts = {}
            for part in without_arrow:gmatch("[^" .. buffer_item_icon .. "]+") do
              table.insert(parts, part)
            end

            -- The filename is the last part (after the icon)
            local filename = parts[#parts]
            if filename then
              -- Trim any leading/trailing whitespace from filename
              filename = filename:match("^%s*(.-)%s*$")
              return { type = "buffer_item", conn_name = parent_info.conn_name, buffer_name = filename }
            end
          elseif parent_info and parent_info.type == "saved" then
            -- This is a saved query item under Saved Queries folder
            -- Line format: "      [icon]  filename"
            -- Extract everything after leading spaces and icon
            local trimmed = line:match("^%s*(.-)%s*$")  -- Remove leading/trailing spaces
            -- Skip the icon (first non-space character) and get the filename
            -- Pattern: skip any non-alphanumeric characters and spaces, then capture the rest
            local filename = trimmed:match("^[^%w%s]*%s*(.+)")
            if filename then
              return { type = "saved_query_item", conn_name = parent_info.conn_name, query_name = filename }
            end
          elseif parent_info and parent_info.type == "tables" then
            -- This is a table item under Tables folder
            -- Extract table name - split by whitespace and take last part
            -- Format: "      ▸   ApplicationEnvironments" or "      ▾   ApplicationEnvironments"
            local parts = {}
            for part in line:gmatch("%S+") do
              table.insert(parts, part)
            end

            local table_name = parts[#parts] -- Last non-whitespace part
            if table_name then
              return { type = "table", conn_name = parent_info.conn_name, table_name = table_name }
            end
          elseif parent_info and parent_info.type == "table" then
            -- This is a sub-item under a table (Columns, List, PKs, FKs, Indexes, CREATE, UPDATE, DROP, DELETE)
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed:match("Columns") then
              return { type = "table_columns", conn_name = parent_info.conn_name, table_name = parent_info.table_name }
            elseif trimmed:match("List") then
              return { type = "table_list", conn_name = parent_info.conn_name, table_name = parent_info.table_name }
            elseif trimmed:match("Primary Keys") then
              return { type = "table_pks", conn_name = parent_info.conn_name, table_name = parent_info.table_name }
            elseif trimmed:match("Foreign Keys") then
              return { type = "table_fks", conn_name = parent_info.conn_name, table_name = parent_info.table_name }
            elseif trimmed:match("Indexes") then
              return { type = "table_indexes", conn_name = parent_info.conn_name, table_name = parent_info.table_name }
            elseif trimmed:match("CREATE Table") then
              return { type = "table_create", conn_name = parent_info.conn_name, table_name = parent_info.table_name }
            elseif trimmed:match("UPDATE Template") then
              return { type = "table_update", conn_name = parent_info.conn_name, table_name = parent_info.table_name }
            elseif trimmed:match("DROP Table") then
              return { type = "table_drop", conn_name = parent_info.conn_name, table_name = parent_info.table_name }
            elseif trimmed:match("DELETE Records") then
              return { type = "table_delete_records", conn_name = parent_info.conn_name, table_name = parent_info.table_name }
            end
          end
          break
        end
      end
    end
  end

  -- Connection line - check if it contains a database icon
  -- Database icons: 󰆼 (sqlite), 󰘐 (sqlserver),  (mysql),  (postgres), 🗄️🔷🐬🐘 (unicode)
  local has_db_icon = line:match("[󰆼󰘐🗄️🔷🐬🐘]")

  if has_db_icon and indent_level <= 4 then
    -- Extract connection name - get the last "word" from the line
    -- Line format: "✗ ▸ 󰆼 example.db" -> we want "example.db"
    local parts = {}
    for part in line:gmatch("%S+") do
      table.insert(parts, part)
    end

    local conn_name = parts[#parts] -- Last non-whitespace part

    if conn_name then
      return { type = "connection", conn_name = conn_name }
    end
  end

  return nil
end

---Generate metadata query based on type
---@param connection table Database connection
---@param table_name string Table name
---@param query_type string Query type (table_columns, table_list, etc.)
---@return string? query SQL query or nil
local function generate_metadata_query(connection, table_name, query_type)
  local db_type = connection.type:lower():gsub("[%s%-_]", "")

  if query_type == "table_list" then
    -- Simple SELECT with database-specific row limiting
    if db_type == "sqlserver" or db_type == "mssql" then
      -- SQL Server uses TOP
      return string.format("SELECT TOP 200 * FROM %s;", table_name)
    else
      -- SQLite, MySQL, PostgreSQL use LIMIT
      return string.format("SELECT * FROM %s LIMIT 200;", table_name)
    end

  elseif query_type == "table_columns" then
    -- Column information query
    if db_type == "sqlite" then
      return string.format("PRAGMA table_info(%s);", table_name)
    elseif db_type == "sqlserver" or db_type == "mssql" then
      return string.format([[
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '%s'
ORDER BY ORDINAL_POSITION;
]], table_name)
    elseif db_type == "mysql" or db_type == "mariadb" then
      return string.format("DESCRIBE %s;", table_name)
    elseif db_type == "postgres" or db_type == "postgresql" then
      return string.format([[
SELECT column_name, data_type, character_maximum_length, is_nullable
FROM information_schema.columns
WHERE table_name = '%s'
ORDER BY ordinal_position;
]], table_name)
    end

  elseif query_type == "table_pks" then
    -- Primary key information
    if db_type == "sqlite" then
      return string.format("PRAGMA table_info(%s);", table_name) -- pk column shows 1 for PKs
    elseif db_type == "sqlserver" or db_type == "mssql" then
      return string.format([[
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
WHERE TABLE_NAME = '%s' AND CONSTRAINT_NAME LIKE 'PK%%'
ORDER BY ORDINAL_POSITION;
]], table_name)
    elseif db_type == "mysql" or db_type == "mariadb" then
      return string.format("SHOW KEYS FROM %s WHERE Key_name = 'PRIMARY';", table_name)
    elseif db_type == "postgres" or db_type == "postgresql" then
      return string.format([[
SELECT a.attname
FROM pg_index i
JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
WHERE i.indrelid = '%s'::regclass AND i.indisprimary;
]], table_name)
    end

  elseif query_type == "table_fks" then
    -- Foreign key information
    if db_type == "sqlite" then
      return string.format("PRAGMA foreign_key_list(%s);", table_name)
    elseif db_type == "sqlserver" or db_type == "mssql" then
      return string.format([[
SELECT
    fk.name AS FK_NAME,
    OBJECT_NAME(fk.parent_object_id) AS TABLE_NAME,
    COL_NAME(fc.parent_object_id, fc.parent_column_id) AS COLUMN_NAME,
    OBJECT_NAME(fk.referenced_object_id) AS REFERENCED_TABLE,
    COL_NAME(fc.referenced_object_id, fc.referenced_column_id) AS REFERENCED_COLUMN
FROM sys.foreign_keys AS fk
INNER JOIN sys.foreign_key_columns AS fc ON fk.object_id = fc.constraint_object_id
WHERE OBJECT_NAME(fk.parent_object_id) = '%s';
]], table_name)
    elseif db_type == "mysql" or db_type == "mariadb" then
      return string.format([[
SELECT
    CONSTRAINT_NAME,
    COLUMN_NAME,
    REFERENCED_TABLE_NAME,
    REFERENCED_COLUMN_NAME
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
WHERE TABLE_NAME = '%s' AND REFERENCED_TABLE_NAME IS NOT NULL;
]], table_name)
    elseif db_type == "postgres" or db_type == "postgresql" then
      return string.format([[
SELECT
    tc.constraint_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_name = '%s';
]], table_name)
    end

  elseif query_type == "table_indexes" then
    -- Index information
    if db_type == "sqlite" then
      return string.format("PRAGMA index_list(%s);", table_name)
    elseif db_type == "sqlserver" or db_type == "mssql" then
      return string.format([[
SELECT
    i.name AS INDEX_NAME,
    i.type_desc AS INDEX_TYPE,
    COL_NAME(ic.object_id, ic.column_id) AS COLUMN_NAME
FROM sys.indexes AS i
INNER JOIN sys.index_columns AS ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
WHERE OBJECT_NAME(i.object_id) = '%s';
]], table_name)
    elseif db_type == "mysql" or db_type == "mariadb" then
      return string.format("SHOW INDEX FROM %s;", table_name)
    elseif db_type == "postgres" or db_type == "postgresql" then
      return string.format([[
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = '%s';
]], table_name)
    end

  elseif query_type == "table_create" then
    -- Generate CREATE TABLE script
    if db_type == "sqlite" then
      -- SQLite: Get schema from sqlite_master
      return string.format("SELECT sql FROM sqlite_master WHERE type='table' AND name='%s';", table_name)

    elseif db_type == "sqlserver" or db_type == "mssql" then
      -- SQL Server: Generate CREATE TABLE from INFORMATION_SCHEMA
      return string.format([[
-- CREATE TABLE script for %s
SELECT
    'CREATE TABLE [' + TABLE_SCHEMA + '].[' + TABLE_NAME + '] (' + CHAR(13) + CHAR(10) +
    STUFF((
        SELECT ',' + CHAR(13) + CHAR(10) + '    [' + COLUMN_NAME + '] ' +
               DATA_TYPE +
               CASE
                   WHEN CHARACTER_MAXIMUM_LENGTH IS NOT NULL
                   THEN '(' + CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR) + ')'
                   ELSE ''
               END +
               CASE WHEN IS_NULLABLE = 'NO' THEN ' NOT NULL' ELSE '' END
        FROM INFORMATION_SCHEMA.COLUMNS c2
        WHERE c2.TABLE_NAME = c.TABLE_NAME AND c2.TABLE_SCHEMA = c.TABLE_SCHEMA
        ORDER BY ORDINAL_POSITION
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)'), 1, 1, '') +
    CHAR(13) + CHAR(10) + ');' AS CreateScript
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE TABLE_NAME = '%s'
GROUP BY TABLE_SCHEMA, TABLE_NAME;
]], table_name, table_name)

    elseif db_type == "mysql" or db_type == "mariadb" then
      -- MySQL: Use SHOW CREATE TABLE
      return string.format("SHOW CREATE TABLE %s;", table_name)

    elseif db_type == "postgres" or db_type == "postgresql" then
      -- PostgreSQL: Generate CREATE TABLE from information_schema
      return string.format([[
-- CREATE TABLE script for %s
SELECT
    'CREATE TABLE ' || table_name || ' (' || E'\n' ||
    string_agg(
        '    ' || column_name || ' ' ||
        data_type ||
        CASE
            WHEN character_maximum_length IS NOT NULL
            THEN '(' || character_maximum_length || ')'
            ELSE ''
        END ||
        CASE WHEN is_nullable = 'NO' THEN ' NOT NULL' ELSE '' END,
        ',' || E'\n'
        ORDER BY ordinal_position
    ) || E'\n' || ');' AS create_script
FROM information_schema.columns
WHERE table_name = '%s'
GROUP BY table_name;
]], table_name, table_name)
    end

  elseif query_type == "table_update" then
    -- Generate UPDATE template with all columns
    if db_type == "sqlite" then
      return string.format([[
-- UPDATE template for %s
-- Get column names first, then build UPDATE statement
SELECT 'UPDATE %s SET ' ||
       group_concat(name || ' = ''value''', ', ') ||
       ' WHERE rowid = 1;' AS update_template
FROM pragma_table_info('%s');
]], table_name, table_name, table_name)

    elseif db_type == "sqlserver" or db_type == "mssql" then
      return string.format([[
-- UPDATE template for %s
SELECT
    'UPDATE [' + TABLE_SCHEMA + '].[' + TABLE_NAME + ']' + CHAR(13) + CHAR(10) +
    'SET ' + CHAR(13) + CHAR(10) +
    STUFF((
        SELECT ',' + CHAR(13) + CHAR(10) + '    [' + COLUMN_NAME + '] = ' +
               CASE
                   WHEN DATA_TYPE IN ('int', 'bigint', 'smallint', 'tinyint', 'decimal', 'numeric', 'float', 'real')
                   THEN '0'
                   WHEN DATA_TYPE IN ('bit')
                   THEN '0'
                   WHEN DATA_TYPE IN ('date', 'datetime', 'datetime2', 'smalldatetime')
                   THEN '''YYYY-MM-DD'''
                   ELSE '''value'''
               END
        FROM INFORMATION_SCHEMA.COLUMNS c2
        WHERE c2.TABLE_NAME = c.TABLE_NAME AND c2.TABLE_SCHEMA = c.TABLE_SCHEMA
        ORDER BY ORDINAL_POSITION
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)'), 1, 1, '') +
    CHAR(13) + CHAR(10) + 'WHERE /* condition */;' AS UpdateTemplate
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE TABLE_NAME = '%s'
GROUP BY TABLE_SCHEMA, TABLE_NAME;
]], table_name, table_name)

    elseif db_type == "mysql" or db_type == "mariadb" then
      return string.format([[
-- UPDATE template for %s
SELECT CONCAT(
    'UPDATE %s SET ', CHAR(10),
    GROUP_CONCAT(
        CONCAT('    ', COLUMN_NAME, ' = ',
            CASE
                WHEN DATA_TYPE IN ('int', 'bigint', 'smallint', 'tinyint', 'decimal', 'numeric', 'float', 'double')
                THEN '0'
                WHEN DATA_TYPE IN ('date', 'datetime', 'timestamp')
                THEN '''YYYY-MM-DD'''
                ELSE '''value'''
            END
        )
        SEPARATOR CONCAT(',', CHAR(10))
    ),
    CHAR(10), 'WHERE /* condition */;'
) AS update_template
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '%s';
]], table_name, table_name, table_name)

    elseif db_type == "postgres" or db_type == "postgresql" then
      return string.format([[
-- UPDATE template for %s
SELECT
    'UPDATE ' || table_name || E'\nSET ' || E'\n' ||
    string_agg(
        '    ' || column_name || ' = ' ||
        CASE
            WHEN data_type IN ('integer', 'bigint', 'smallint', 'numeric', 'decimal', 'real', 'double precision')
            THEN '0'
            WHEN data_type IN ('boolean')
            THEN 'false'
            WHEN data_type IN ('date', 'timestamp', 'timestamp without time zone', 'timestamp with time zone')
            THEN '''YYYY-MM-DD'''
            ELSE '''value'''
        END,
        ',' || E'\n'
        ORDER BY ordinal_position
    ) || E'\nWHERE /* condition */;' AS update_template
FROM information_schema.columns
WHERE table_name = '%s'
GROUP BY table_name;
]], table_name, table_name)
    end

  elseif query_type == "table_drop" then
    -- Generate DROP TABLE script
    if db_type == "sqlite" then
      return string.format("DROP TABLE %s;", table_name)

    elseif db_type == "sqlserver" or db_type == "mssql" then
      return string.format([[
-- DROP TABLE script for %s
DROP TABLE [dbo].[%s];
]], table_name, table_name)

    elseif db_type == "mysql" or db_type == "mariadb" then
      return string.format("DROP TABLE %s;", table_name)

    elseif db_type == "postgres" or db_type == "postgresql" then
      return string.format("DROP TABLE %s;", table_name)
    end

  elseif query_type == "table_delete_records" then
    -- Generate DELETE FROM script with WHERE template (safer)
    if db_type == "sqlite" then
      return string.format([[
-- DELETE records from %s
-- WARNING: This will delete records. Uncomment and modify WHERE clause before executing.
DELETE FROM %s
WHERE rowid = ?;
]], table_name, table_name)

    elseif db_type == "sqlserver" or db_type == "mssql" then
      return string.format([[
-- DELETE records from %s
-- WARNING: This will delete records. Modify WHERE clause before executing.
DELETE FROM [dbo].[%s]
WHERE /* Add your condition here, e.g., [Id] = 1 */;
]], table_name, table_name)

    elseif db_type == "mysql" or db_type == "mariadb" then
      return string.format([[
-- DELETE records from %s
-- WARNING: This will delete records. Modify WHERE clause before executing.
DELETE FROM %s
WHERE /* Add your condition here, e.g., id = 1 */;
]], table_name, table_name)

    elseif db_type == "postgres" or db_type == "postgresql" then
      return string.format([[
-- DELETE records from %s
-- WARNING: This will delete records. Modify WHERE clause before executing.
DELETE FROM %s
WHERE /* Add your condition here, e.g., id = 1 */;
]], table_name, table_name)
    end
  end

  return nil
end

---Execute a query and return raw output (for script generation)
---@param connection table Database connection
---@param query string SQL query
---@return string? output Raw query output or nil
local function execute_query_for_script(connection, query)
  local db_type = connection.type:lower():gsub("[%s%-_]", "")

  -- Remove SQL comments (-- style) to avoid issues with command-line parsing
  local clean_query = query:gsub("%-%-[^\n]*\n", "\n")
  clean_query = vim.trim(clean_query)

  if db_type == "sqlite" then
    local db_path = vim.fn.expand(connection.path)
    local output = vim.fn.system({
      'sqlite3',
      db_path,
      clean_query
    })

    if vim.v.shell_error == 0 and output and #output > 0 then
      return output
    end

  elseif db_type == "sqlserver" or db_type == "mssql" then
    local cmd = {
      'sqlcmd',
      '-S', connection.server or connection.host,
      '-d', connection.database,
    }

    if connection.user or connection.username then
      table.insert(cmd, '-U')
      table.insert(cmd, connection.user or connection.username)
      if connection.password then
        table.insert(cmd, '-P')
        table.insert(cmd, connection.password)
      end
    else
      table.insert(cmd, '-E')
    end

    -- Trust server certificate (for self-signed certs)
    if connection.trust_server_certificate ~= false then
      table.insert(cmd, '-C')
    end

    table.insert(cmd, '-Q')
    table.insert(cmd, query)
    table.insert(cmd, '-h')
    table.insert(cmd, '-1')

    local output = vim.fn.system(cmd)

    if vim.v.shell_error == 0 then
      return output
    end

  elseif db_type == "mysql" or db_type == "mariadb" then
    local cmd = {
      'mysql',
      '-h', connection.host or 'localhost',
      '-D', connection.database,
      '-N', -- No column names
      '-B', -- Batch mode
    }

    if connection.user then
      table.insert(cmd, '-u')
      table.insert(cmd, connection.user)
    end

    if connection.password then
      table.insert(cmd, '-p' .. connection.password)
    end

    table.insert(cmd, '-e')
    table.insert(cmd, query)

    local output = vim.fn.system(cmd)

    if vim.v.shell_error == 0 then
      return output
    end

  elseif db_type == "postgres" or db_type == "postgresql" then
    local cmd = {
      'psql',
      '-h', connection.host or 'localhost',
      '-d', connection.database,
      '-t', -- Tuples only (no headers)
      '-A', -- Unaligned output
    }

    if connection.user then
      table.insert(cmd, '-U')
      table.insert(cmd, connection.user)
    end

    table.insert(cmd, '-c')
    table.insert(cmd, query)

    local output = vim.fn.system(cmd)

    if vim.v.shell_error == 0 then
      return output
    end
  end

  return nil
end

---Parse script from query output
---@param output string Raw query output
---@param db_type string Database type
---@param script_type string Script type (table_create or table_update)
---@return string? script Parsed script or nil
local function parse_script_from_output(output, db_type, script_type)
  -- Trim whitespace
  local script = vim.trim(output)

  -- For SQLite CREATE, the output is the CREATE TABLE statement directly
  if db_type == "sqlite" and script_type == "table_create" then
    return script
  end

  -- For MySQL SHOW CREATE TABLE, output is: tablename\tCREATE TABLE ...
  if (db_type == "mysql" or db_type == "mariadb") and script_type == "table_create" then
    -- Split by tab and take the second part
    local parts = vim.split(script, "\t")
    if #parts >= 2 then
      return parts[2]
    end
    return script
  end

  -- For other databases, the output should be the script itself
  -- Just return it cleaned up
  return script
end

---Generate table script (CREATE, UPDATE, DROP, DELETE) by executing metadata query and extracting result
---@param connection table Database connection
---@param table_name string Table name
---@param script_type string Script type (table_create, table_update, table_drop, table_delete_records)
---@return string? script Generated script or nil
local function generate_table_script(connection, table_name, script_type)
  -- For DROP and DELETE, we can generate directly without executing a query
  local db_type = connection.type:lower():gsub("[%s%-_]", "")

  if script_type == "table_drop" then
    if db_type == "sqlserver" or db_type == "mssql" then
      return string.format("-- DROP TABLE script for %s\nDROP TABLE [dbo].[%s];", table_name, table_name)
    else
      return string.format("-- DROP TABLE script for %s\nDROP TABLE %s;", table_name, table_name)
    end

  elseif script_type == "table_delete_records" then
    if db_type == "sqlite" then
      return string.format([[-- DELETE records from %s
-- WARNING: This will delete records. Modify WHERE clause before executing.
DELETE FROM %s
WHERE rowid = ?;]], table_name, table_name)
    elseif db_type == "sqlserver" or db_type == "mssql" then
      return string.format([[-- DELETE records from %s
-- WARNING: This will delete records. Modify WHERE clause before executing.
DELETE FROM [dbo].[%s]
WHERE /* Add your condition here, e.g., [Id] = 1 */;]], table_name, table_name)
    else
      return string.format([[-- DELETE records from %s
-- WARNING: This will delete records. Modify WHERE clause before executing.
DELETE FROM %s
WHERE /* Add your condition here, e.g., id = 1 */;]], table_name, table_name)
    end

  elseif script_type == "table_create" or script_type == "table_update" then
    -- For CREATE and UPDATE, we need to execute a metadata query and extract the result
    local query = generate_metadata_query(connection, table_name, script_type)
    if not query then
      return nil
    end

    -- Execute the query and get raw output
    local output = execute_query_for_script(connection, query)
    if not output then
      return string.format("-- Failed to generate %s script for %s", script_type, table_name)
    end

    -- Parse the output to extract the actual script
    local script = parse_script_from_output(output, db_type, script_type)
    return script or string.format("-- Failed to parse %s script for %s", script_type, table_name)
  end

  return nil
end

---Create new buffer with script (NO auto-execution)
---@param connection table Database connection
---@param script string SQL script content
---@param context string Context for filename (e.g., "users-create", "products-update")
local function create_script_buffer(connection, script, context)
  -- Create tmp file
  local tmp_dir = get_connection_tmp_dir(connection)
  local filename = string.format(
    "%s/%s-%s.sql",
    tmp_dir,
    os.date("%Y-%m-%d-%H%M%S"),
    context
  )

  -- Write script to file
  vim.fn.writefile(vim.split(script, "\n"), filename)

  -- Switch to query editor window
  if query_editor_win and vim.api.nvim_win_is_valid(query_editor_win) then
    vim.api.nvim_set_current_win(query_editor_win)
  end

  -- Open file-backed buffer
  vim.cmd('edit ' .. vim.fn.fnameescape(filename))
  local buf = vim.api.nvim_get_current_buf()

  -- Store connection info
  vim.b[buf].enhance_connection = connection

  -- Set up keymaps
  require("enhance.query").setup_keymaps(buf)

  -- Track this buffer
  add_buffer_to_tracking(connection.name, buf, filename)

  -- Refresh explorer to show new buffer
  refresh_explorer()

  -- NO auto-execution - user must manually run with <F5>
end

---Create new buffer with query and auto-execute (switches query editor buffer)
---@param connection table Database connection
---@param query string SQL query
---@param context string Context for filename (e.g., "users-list", "products-columns")
local function create_and_execute_query(connection, query, context)
  -- Create tmp file
  local tmp_dir = get_connection_tmp_dir(connection)
  local filename = string.format(
    "%s/%s-%s.sql",
    tmp_dir,
    os.date("%Y-%m-%d-%H%M%S"),
    context
  )

  -- Write query to file
  vim.fn.writefile(vim.split(query, "\n"), filename)

  -- Switch to query editor window
  if query_editor_win and vim.api.nvim_win_is_valid(query_editor_win) then
    vim.api.nvim_set_current_win(query_editor_win)
  end

  -- Open file-backed buffer
  vim.cmd('edit ' .. vim.fn.fnameescape(filename))
  local buf = vim.api.nvim_get_current_buf()

  -- Store connection info
  vim.b[buf].enhance_connection = connection

  -- Set up keymaps
  require("enhance.query").setup_keymaps(buf)

  -- Track this buffer
  add_buffer_to_tracking(connection.name, buf, filename)

  -- Refresh explorer to show new buffer
  refresh_explorer()

  -- Auto-execute the query
  vim.schedule(function()
    require("enhance.executor").execute(connection, query)
  end)
end

---Handle Enter key press in explorer
---@param line_num number Current line number
local function handle_enter(line_num)
  local lines = vim.api.nvim_buf_get_lines(explorer_buf, 0, -1, false)
  local line = lines[line_num]

  if not line or line == "" then
    return
  end

  local info = parse_line(line, line_num)
  if not info then
    return
  end

  local connections = require("enhance.connections")

  if info.type == "connection" then
    -- Test connection before expanding
    local conn = connections.get_connection(info.conn_name)
    if not conn then
      return
    end

    -- Test the connection
    vim.notify("Testing connection to " .. conn.name .. "...", vim.log.levels.INFO)
    local executor = require("enhance.executor")
    local success, error_msg = executor.test_connection(conn)

    if not success then
      -- Connection failed - show error, keep X, don't expand
      vim.notify("Connection failed: " .. (error_msg or "Unknown error"), vim.log.levels.ERROR)
      return
    end

    -- Connection succeeded - set as current, expand tree, show checkmark
    connections.set_current(conn)
    active_connection = conn  -- Track active connection for new queries

    -- Convert current query editor buffer to tmp file (if it doesn't have one)
    if query_editor_win and vim.api.nvim_win_is_valid(query_editor_win) then
      local query_buf = vim.api.nvim_win_get_buf(query_editor_win)
      if query_buf and vim.api.nvim_buf_is_valid(query_buf) then
        -- Only convert if buffer doesn't already have a connection
        if not vim.b[query_buf].enhance_connection then
          -- Get current buffer content
          local lines = vim.api.nvim_buf_get_lines(query_buf, 0, -1, false)

          -- Create tmp file
          local tmp_dir = get_connection_tmp_dir(conn)
          local filename = string.format(
            "%s/%s-editor.sql",
            tmp_dir,
            os.date("%Y-%m-%d-%H%M%S")
          )

          -- Write content to file
          vim.fn.writefile(lines, filename)

          -- Switch to file-backed buffer
          vim.api.nvim_set_current_win(query_editor_win)
          vim.cmd('edit ' .. vim.fn.fnameescape(filename))

          -- Get new buffer number
          local new_buf = vim.api.nvim_get_current_buf()

          -- Set connection on new buffer
          vim.b[new_buf].enhance_connection = conn

          -- Set up keymaps
          require("enhance.query").setup_keymaps(new_buf)

          -- Track this buffer
          add_buffer_to_tracking(conn.name, new_buf, filename)
        end
      end
    end

    local conn_key = "conn:" .. conn.name
    expanded[conn_key] = not expanded[conn_key]

    -- Refresh to show checkmark and expanded tree
    refresh_explorer()

  elseif info.type == "new_query" then
    -- Create new empty query buffer
    M.new_query()

  elseif info.type == "buffers" then
    -- Toggle buffers folder expansion
    local conn = connections.get_connection(info.conn_name)
    if conn then
      local key = "conn:" .. conn.name .. ":buffers"
      expanded[key] = not expanded[key]
      refresh_explorer()
    end

  elseif info.type == "buffer_item" then
    -- Check if buffer has results - if so, toggle expansion; otherwise open buffer
    local conn = connections.get_connection(info.conn_name)
    if conn then
      local buffers = get_buffers_for_connection(conn.name)
      for _, buf_info in ipairs(buffers) do
        local display_name = get_buffer_display_name(buf_info.filepath)
        if display_name == info.buffer_name then
          -- Check if buffer has results
          local result_bufnr = get_result_buffer_info(buf_info.bufnr)
          local has_results = result_bufnr and vim.api.nvim_buf_is_valid(result_bufnr)

          if has_results then
            -- Toggle buffer expansion to show/hide results
            local key = "conn:" .. conn.name .. ":buffer:" .. display_name
            expanded[key] = not expanded[key]
            refresh_explorer()
          else
            -- No results - open the buffer
            -- Switch to query editor window
            if query_editor_win and vim.api.nvim_win_is_valid(query_editor_win) then
              vim.api.nvim_set_current_win(query_editor_win)

              -- If buffer exists, switch to it; otherwise open the file
              if buf_info.bufnr ~= -1 and vim.api.nvim_buf_is_valid(buf_info.bufnr) then
                vim.api.nvim_win_set_buf(query_editor_win, buf_info.bufnr)
              else
                -- Open the file
                vim.cmd('edit ' .. vim.fn.fnameescape(buf_info.filepath))
                local new_buf = vim.api.nvim_get_current_buf()

                -- Set connection on buffer
                vim.b[new_buf].enhance_connection = conn

                -- Set up keymaps
                require("enhance.query").setup_keymaps(new_buf)

                -- Track this buffer
                add_buffer_to_tracking(conn.name, new_buf, buf_info.filepath)
              end
            end
          end
          break
        end
      end
    end

  elseif info.type == "result_item" then
    -- Display the result buffer in results window
    -- Find the parent buffer by looking at the line above
    local lines = vim.api.nvim_buf_get_lines(explorer_buf, 0, -1, false)
    local parent_line = lines[info.line_num - 1]
    if parent_line then
      local parent_info = parse_line(parent_line, info.line_num - 1)
      if parent_info and parent_info.type == "buffer_item" then
        -- Get the buffer info
        local conn = connections.get_connection(info.conn_name)
        if conn then
          local buffers = get_buffers_for_connection(conn.name)
          for _, buf_info in ipairs(buffers) do
            local display_name = get_buffer_display_name(buf_info.filepath)
            if display_name == parent_info.buffer_name then
              -- Get the result buffer
              local result_bufnr = get_result_buffer_info(buf_info.bufnr)
              if result_bufnr and vim.api.nvim_buf_is_valid(result_bufnr) then
                -- Open or reuse results window
                M.open_results()

                -- Display the result buffer
                if results_win and vim.api.nvim_win_is_valid(results_win) then
                  vim.api.nvim_win_set_buf(results_win, result_bufnr)
                end
              end
              break
            end
          end
        end
      end
    end

  elseif info.type == "saved_query_item" then
    -- Open saved query
    local conn = connections.get_connection(info.conn_name)
    if conn then
      local queries = get_saved_queries_for_connection(conn.name)
      for _, query_info in ipairs(queries) do
        local display_name = get_buffer_display_name(query_info.filepath)
        if display_name == info.query_name then
          -- Switch to query editor window
          if query_editor_win and vim.api.nvim_win_is_valid(query_editor_win) then
            vim.api.nvim_set_current_win(query_editor_win)

            -- If buffer exists, switch to it; otherwise open the file
            if query_info.bufnr ~= -1 and vim.api.nvim_buf_is_valid(query_info.bufnr) then
              vim.api.nvim_win_set_buf(query_editor_win, query_info.bufnr)
            else
              -- Open the file
              vim.cmd('edit ' .. vim.fn.fnameescape(query_info.filepath))
              local new_buf = vim.api.nvim_get_current_buf()

              -- Set connection on buffer
              vim.b[new_buf].enhance_connection = conn

              -- Set up keymaps
              require("enhance.query").setup_keymaps(new_buf)
            end
          end
          break
        end
      end
    end

  elseif info.type == "tables" or info.type == "saved" then
    -- Toggle folder expansion
    local conn = connections.get_connection(info.conn_name)
    if conn then
      local key = "conn:" .. conn.name .. ":" .. info.type
      expanded[key] = not expanded[key]
      refresh_explorer()
    end

  elseif info.type == "table" then
    -- Toggle table expansion to show sub-items
    local conn = connections.get_connection(info.conn_name)
    if conn then
      local key = "conn:" .. conn.name .. ":table:" .. info.table_name
      expanded[key] = not expanded[key]
      refresh_explorer()
    end

  elseif info.type == "table_columns" or info.type == "table_list" or
         info.type == "table_pks" or info.type == "table_fks" or info.type == "table_indexes" then
    -- Generate metadata query in new buffer (no auto-execution)
    local conn = connections.get_connection(info.conn_name)
    if conn then
      local query = generate_metadata_query(conn, info.table_name, info.type)
      if query then
        -- Create new buffer with query (user must manually execute with <F5>)
        local context = string.format("%s-%s", info.table_name, info.type:lower())
        create_script_buffer(conn, query, context)
      end
    end

  elseif info.type == "table_create" or info.type == "table_update" or
         info.type == "table_drop" or info.type == "table_delete_records" then
    -- Generate script (no auto-execution)
    local conn = connections.get_connection(info.conn_name)
    if conn then
      local script = generate_table_script(conn, info.table_name, info.type)
      if script then
        local context = string.format("%s-%s", info.table_name, info.type:lower())
        create_script_buffer(conn, script, context)
      end
    end
  end
end

---Start enhance workspace (creates initial layout)
function M.start()
  -- If workspace already initialized, do nothing
  if workspace_initialized then
    vim.notify("Enhance workspace already started", vim.log.levels.INFO)
    return
  end

  -- Create a new tab for clean database workspace
  vim.cmd('tabnew')
  explorer_tab = vim.api.nvim_get_current_tabpage()
  workspace_initialized = true

  -- Set up autocmd to handle saving tmp buffers
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    pattern = "*/enhance.nvim/*/tmp/*.sql",
    callback = function(args)
      return handle_tmp_buffer_save(args.buf)
    end,
    desc = "Handle saving enhance.nvim tmp buffers to queries directory"
  })

  -- Set up autocmd to clean up buffer tracking when buffers are deleted
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    callback = function(args)
      remove_buffer_from_tracking(args.buf)
    end,
    desc = "Clean up enhance.nvim buffer tracking on buffer deletion"
  })

  -- Create buffer if needed
  if not explorer_buf or not vim.api.nvim_buf_is_valid(explorer_buf) then
    explorer_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[explorer_buf].filetype = 'enhance-explorer'
    vim.bo[explorer_buf].bufhidden = 'hide'
    vim.bo[explorer_buf].modifiable = false

    -- Define highlight groups
    vim.api.nvim_set_hl(0, 'EnhanceConnected', { fg = '#a6e3a1', bold = true }) -- Green
    vim.api.nvim_set_hl(0, 'EnhanceDisconnected', { fg = '#f38ba8', bold = true }) -- Red
    vim.api.nvim_set_hl(0, 'EnhanceCount', { fg = '#f38ba8' }) -- Red/orange for counts
    vim.api.nvim_set_hl(0, 'EnhanceIconBlue', { fg = '#89b4fa' }) -- Blue for folder icons and items
    vim.api.nvim_set_hl(0, 'EnhanceIconOrange', { fg = '#fab387' }) -- Orange for parent/associated queries
    vim.api.nvim_set_hl(0, 'EnhanceIconPurple', { fg = '#cba6f7' }) -- Purple for result buffers

    -- Set up keymaps
    vim.keymap.set('n', '<CR>', function()
      handle_enter(vim.fn.line('.'))
    end, { buffer = explorer_buf, desc = "Expand/Connect" })

    vim.keymap.set('n', 'q', function()
      M.close()
    end, { buffer = explorer_buf, desc = "Close explorer" })

    vim.keymap.set('n', '<leader>de', function()
      M.toggle()
    end, { buffer = explorer_buf, desc = "Toggle explorer" })

    vim.keymap.set('n', 'R', function()
      M.refresh()
    end, { buffer = explorer_buf, desc = "Refresh explorer" })

    -- Single line deletion with dd
    vim.keymap.set('n', 'dd', function()
      local line_num = vim.fn.line('.')
      local lines = vim.api.nvim_buf_get_lines(explorer_buf, 0, -1, false)
      local line = lines[line_num]
      local info = parse_line(line, line_num)

      if info and (info.type == "buffer_item" or info.type == "saved_query_item") then
        local filename = info.buffer_name or info.query_name
        if filename then
          M.delete_file(filename)
        end
      end
    end, { buffer = explorer_buf, desc = "Delete file under cursor" })

    -- Single line deletion with D (same as dd)
    vim.keymap.set('n', 'D', function()
      local line_num = vim.fn.line('.')
      local lines = vim.api.nvim_buf_get_lines(explorer_buf, 0, -1, false)
      local line = lines[line_num]
      local info = parse_line(line, line_num)

      if info and (info.type == "buffer_item" or info.type == "saved_query_item") then
        local filename = info.buffer_name or info.query_name
        if filename then
          M.delete_file(filename)
        end
      end
    end, { buffer = explorer_buf, desc = "Delete file under cursor" })

    -- Visual mode bulk deletion with d
    -- Use :<C-u> to preserve visual marks and pass range to function
    vim.keymap.set('v', 'd', ':<C-u>lua require("enhance.explorer")._visual_delete()<CR>', { buffer = explorer_buf, desc = "Delete selected files", silent = true })

    -- Visual mode bulk deletion with D (same as d)
    vim.keymap.set('v', 'D', ':<C-u>lua require("enhance.explorer")._visual_delete()<CR>', { buffer = explorer_buf, desc = "Delete selected files", silent = true })
  end

  -- Create window (left drawer, full height)
  local width = 35 -- TODO: Make configurable
  vim.cmd('topleft vsplit')
  explorer_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(explorer_win, explorer_buf)
  vim.api.nvim_win_set_width(explorer_win, width)

  -- Window options
  vim.wo[explorer_win].number = false
  vim.wo[explorer_win].relativenumber = false
  vim.wo[explorer_win].signcolumn = 'no'
  vim.wo[explorer_win].foldcolumn = '0'
  vim.wo[explorer_win].cursorline = true

  -- Build content AFTER window is created
  refresh_explorer()

  -- Create empty query editor on the right
  -- Move to the right window (created by vsplit)
  vim.cmd('wincmd l')

  -- Track the query editor window
  query_editor_win = vim.api.nvim_get_current_win()

  -- Create a new empty buffer for query editing
  local query_buf = vim.api.nvim_create_buf(true, false) -- listed, not scratch
  vim.api.nvim_win_set_buf(query_editor_win, query_buf)

  -- Set SQL filetype for syntax highlighting and LSP
  vim.bo[query_buf].filetype = 'sql'
  vim.bo[query_buf].buftype = ''

  -- Set a descriptive buffer name
  pcall(vim.api.nvim_buf_set_name, query_buf, 'Enhance: Editor')

  -- Set up query execution keymaps (same as <leader>dq)
  require("enhance.query").setup_keymaps(query_buf)

  -- Focus the query editor so user can start typing
  vim.api.nvim_set_current_win(query_editor_win)
end

---Open explorer drawer (show if hidden)
function M.open()
  if not workspace_initialized then
    vim.notify("Run :EnhanceStart first to initialize workspace", vim.log.levels.WARN)
    return
  end

  if explorer_win and vim.api.nvim_win_is_valid(explorer_win) then
    -- Already open, just focus it
    vim.api.nvim_set_current_win(explorer_win)
    return
  end

  -- Create window (left drawer, full height)
  local width = 35 -- TODO: Make configurable
  vim.cmd('topleft vsplit')
  explorer_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(explorer_win, explorer_buf)
  vim.api.nvim_win_set_width(explorer_win, width)

  -- Window options
  vim.wo[explorer_win].number = false
  vim.wo[explorer_win].relativenumber = false
  vim.wo[explorer_win].signcolumn = 'no'
  vim.wo[explorer_win].foldcolumn = '0'
  vim.wo[explorer_win].cursorline = true

  -- Refresh content
  refresh_explorer()
end

---Close explorer drawer
function M.close()
  if explorer_win and vim.api.nvim_win_is_valid(explorer_win) then
    vim.api.nvim_win_close(explorer_win, false)
    explorer_win = nil
  end
end

---Toggle explorer drawer
function M.toggle()
  if explorer_win and vim.api.nvim_win_is_valid(explorer_win) then
    M.close()
  else
    M.open()
  end
end

---Stop enhance workspace (cleanup all buffers)
function M.stop()
  if not workspace_initialized then
    vim.notify("Enhance workspace not started", vim.log.levels.WARN)
    return
  end

  -- Close explorer
  M.close()

  -- Close the enhance tab (force close without saving)
  if explorer_tab and vim.api.nvim_tabpage_is_valid(explorer_tab) then
    -- Switch to the enhance tab first
    vim.api.nvim_set_current_tabpage(explorer_tab)
    -- Force close the tab
    vim.cmd('tabclose!')
  end

  -- Reset state
  workspace_initialized = false
  explorer_tab = nil
  explorer_buf = nil
  query_editor_win = nil
  results_win = nil
  active_connection = nil
  expanded = {}
  table_cache = {}
  connection_buffers = {}

  vim.notify("Enhance workspace stopped", vim.log.levels.INFO)
end

---Check if explorer is open
---@return boolean
function M.is_open()
  return explorer_win ~= nil and vim.api.nvim_win_is_valid(explorer_win)
end

---Check if workspace is initialized
---@return boolean
function M.is_initialized()
  return workspace_initialized
end

---Refresh the explorer (clear cache and redraw)
function M.refresh()
  if not M.is_open() then
    vim.notify("Explorer is not open", vim.log.levels.WARN)
    return
  end

  -- Clear table cache to force refresh
  table_cache = {}

  -- Redraw the explorer
  refresh_explorer()

  vim.notify("Explorer refreshed", vim.log.levels.INFO)
end

---Get the results window ID (for results module to reuse)
---@return number? Window ID or nil
function M.get_results_window()
  return results_win
end

---Set the results window ID (called by results module)
---@param win_id number Window ID
function M.set_results_window(win_id)
  results_win = win_id
end

---Set the last results buffer (called by results module)
---@param buf_id number Buffer ID
function M.set_last_results_buffer(buf_id)
  last_results_buf = buf_id
end

---Close results window
function M.close_results()
  if results_win and vim.api.nvim_win_is_valid(results_win) then
    vim.api.nvim_win_close(results_win, false)
    results_win = nil
  end
end

---Open results window (create if needed)
function M.open_results()
  if not workspace_initialized then
    vim.notify("Run :EnhanceStart first to initialize workspace", vim.log.levels.WARN)
    return
  end

  if results_win and vim.api.nvim_win_is_valid(results_win) then
    -- Already open, just focus it
    vim.api.nvim_set_current_win(results_win)
    return
  end

  -- Create results window (bottom split)
  -- Focus query editor first to split from there
  if query_editor_win and vim.api.nvim_win_is_valid(query_editor_win) then
    vim.api.nvim_set_current_win(query_editor_win)
  end

  vim.cmd('split')
  results_win = vim.api.nvim_get_current_win()

  -- Check if there's an active query buffer with results
  local buf
  if query_editor_win and vim.api.nvim_win_is_valid(query_editor_win) then
    local active_buf = vim.api.nvim_win_get_buf(query_editor_win)
    local result_bufnr = get_result_buffer_info(active_buf)

    if result_bufnr and vim.api.nvim_buf_is_valid(result_bufnr) then
      -- Show results for active query buffer
      buf = result_bufnr
    end
  end

  -- If no active buffer results, create placeholder buffer
  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = 'enhance-results'
    pcall(vim.api.nvim_buf_set_name, buf, '[Enhance] Results')

    -- Set placeholder text BEFORE making it non-modifiable
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "No results yet. Execute a query to see results here." })
    vim.bo[buf].modifiable = false
  end

  vim.api.nvim_win_set_buf(results_win, buf)
end

---Toggle results window visibility
function M.toggle_results()
  if results_win and vim.api.nvim_win_is_valid(results_win) then
    M.close_results()
  else
    M.open_results()
  end
end

---Create new empty query buffer
function M.new_query()
  if not workspace_initialized then
    vim.notify("Run :EnhanceStart first to initialize workspace", vim.log.levels.WARN)
    return
  end

  if not active_connection then
    vim.notify("Connect to a database first", vim.log.levels.WARN)
    return
  end

  -- Create tmp file
  local tmp_dir = get_connection_tmp_dir(active_connection)
  local filename = string.format(
    "%s/%s-new-query.sql",
    tmp_dir,
    os.date("%Y-%m-%d-%H%M%S")
  )

  -- Switch to query editor window
  if query_editor_win and vim.api.nvim_win_is_valid(query_editor_win) then
    vim.api.nvim_set_current_win(query_editor_win)
  end

  -- Create file-backed buffer
  vim.cmd('edit ' .. vim.fn.fnameescape(filename))
  local buf = vim.api.nvim_get_current_buf()

  -- Associate with active connection
  vim.b[buf].enhance_connection = active_connection

  -- Set up query execution keymaps
  require("enhance.query").setup_keymaps(buf)

  -- Track this buffer (will appear in buffer list even before saving)
  add_buffer_to_tracking(active_connection.name, buf, filename)

  -- Refresh explorer to show new buffer in list
  refresh_explorer()
end

---Delete a file (tmp or saved query)
---@param filename string? Optional filename to delete. If not provided, deletes current buffer
function M.delete_file(filename)
  -- If no filename provided, delete current buffer in query editor
  if not filename or filename == "" then
    if not query_editor_win or not vim.api.nvim_win_is_valid(query_editor_win) then
      vim.notify("No query editor window found", vim.log.levels.ERROR)
      return
    end

    local bufnr = vim.api.nvim_win_get_buf(query_editor_win)
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    if filepath == "" then
      vim.notify("Current buffer has no file", vim.log.levels.ERROR)
      return
    end

    delete_file_impl(filepath)
    return
  end

  -- Filename provided: search for it
  if not active_connection then
    vim.notify("No active connection", vim.log.levels.ERROR)
    return
  end

  local filepath = find_file_by_name(filename, active_connection.name)
  if not filepath then
    vim.notify("File not found: " .. filename, vim.log.levels.ERROR)
    return
  end

  delete_file_impl(filepath)
end

---Delete multiple files in bulk (with single confirmation)
---@param filenames string[] List of filenames to delete
function M.delete_files_bulk(filenames)
  if not filenames or #filenames == 0 then
    vim.notify("No files to delete", vim.log.levels.WARN)
    return
  end

  if not active_connection then
    vim.notify("No active connection", vim.log.levels.ERROR)
    return
  end

  -- Resolve all filenames to filepaths
  local filepaths = {}
  for _, filename in ipairs(filenames) do
    local filepath = find_file_by_name(filename, active_connection.name)
    if filepath then
      table.insert(filepaths, filepath)
    end
  end

  if #filepaths == 0 then
    vim.notify("No valid files found to delete", vim.log.levels.WARN)
    return
  end

  -- Show confirmation prompt (using same style as single file deletion)
  local count = #filepaths
  local message = string.format("Delete %d file%s?", count, count > 1 and "s" or "")

  confirm_delete(message, function(confirmed)
    if confirmed then
      -- Delete all files
      local deleted_count = 0
      local failed_files = {}

      for _, filepath in ipairs(filepaths) do
        -- Get buffer number if file is open
        local bufnr = vim.fn.bufnr(filepath)

        -- Delete the file with error handling
        local ok, result = pcall(vim.fn.delete, filepath)
        if ok and result == 0 then
          deleted_count = deleted_count + 1

          -- Close buffer if it was open
          if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
            -- Remove from tracking first
            remove_buffer_from_tracking(bufnr)

            -- If it's the current buffer in query editor, switch to a scratch buffer
            if query_editor_win and vim.api.nvim_win_is_valid(query_editor_win) then
              local current_buf = vim.api.nvim_win_get_buf(query_editor_win)
              if bufnr == current_buf then
                local scratch_buf = vim.api.nvim_create_buf(false, true)
                vim.bo[scratch_buf].filetype = 'sql'
                pcall(vim.api.nvim_buf_set_name, scratch_buf, '[Enhance] Editor')
                vim.api.nvim_win_set_buf(query_editor_win, scratch_buf)
              end
            end

            -- Delete the buffer
            vim.api.nvim_buf_delete(bufnr, { force = true })
          end
        else
          -- Track failed deletions
          local filename = vim.fn.fnamemodify(filepath, ':t')
          table.insert(failed_files, filename)
        end
      end

      -- Refresh explorer
      refresh_explorer()

      -- Show result
      if deleted_count > 0 then
        vim.notify(
          string.format("Deleted %d file%s", deleted_count, deleted_count > 1 and "s" or ""),
          vim.log.levels.INFO
        )
      end

      if #failed_files > 0 then
        vim.notify(
          string.format("Failed to delete %d file%s: %s",
            #failed_files,
            #failed_files > 1 and "s" or "",
            table.concat(failed_files, ", ")
          ),
          vim.log.levels.ERROR
        )
      end
    end
  end)
end

---Visual mode delete helper (called from visual mode keymap)
function M._visual_delete()
  -- Get visual selection range
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]

  -- Get all lines in buffer
  local lines = vim.api.nvim_buf_get_lines(explorer_buf, 0, -1, false)

  -- Collect files to delete
  local files_to_delete = {}
  for line_num = start_line, end_line do
    if line_num > 0 and line_num <= #lines then
      local line = lines[line_num]
      local info = parse_line(line, line_num)

      if info and (info.type == "buffer_item" or info.type == "saved_query_item") then
        local filename = info.buffer_name or info.query_name
        if filename then
          table.insert(files_to_delete, filename)
        end
      end
    end
  end

  -- Delete collected files
  if #files_to_delete > 0 then
    M.delete_files_bulk(files_to_delete)
  else
    vim.notify("No files selected for deletion", vim.log.levels.WARN)
  end
end

-- Expose for testing
M._build_explorer_content = build_explorer_content
M._get_db_icon = get_db_icon
M._get_node_icon = get_node_icon
M._parse_line = parse_line
M._cleanup_invalid_buffers = cleanup_invalid_buffers
M._remove_buffer_from_tracking = remove_buffer_from_tracking
M._get_connection_tmp_dir = get_connection_tmp_dir
M._get_connection_queries_dir = get_connection_queries_dir

-- Expose for results module
M.associate_result_buffer = associate_result_buffer
M.get_result_buffer_info = get_result_buffer_info
M.refresh_explorer = refresh_explorer

return M
