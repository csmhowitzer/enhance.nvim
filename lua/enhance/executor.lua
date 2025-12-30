-- enhance.nvim - Query executor
-- Executes database queries using CLI tools (sqlite3, psql, etc.)

local M = {}

---Count rows from query output and remove footer lines
---Handles both SELECT queries (counts data rows) and DML queries (parses "rows affected")
---Modifies output_lines in place to remove database footer messages
---@param output_lines string[] Query output lines (modified in place)
---@param db_type string Database type
---@return number Row count or rows affected
local function count_rows(output_lines, db_type)
  local normalized_type = db_type:lower():gsub("[%s%-_]", "")
  local row_count = 0

  -- Try to parse "rows affected" message first (INSERT/UPDATE/DELETE)
  if normalized_type == "sqlserver" or normalized_type == "mssql" then
    for i = #output_lines, 1, -1 do
      local line = output_lines[i]
      local count = line:match("%((%d+) rows? affected%)")
      if count then
        row_count = tonumber(count)
        table.remove(output_lines, i)  -- Remove the footer line
      end
    end
    if row_count > 0 then
      return row_count
    end
  elseif normalized_type == "mysql" or normalized_type == "mariadb" then
    for i = #output_lines, 1, -1 do
      local line = output_lines[i]
      local count = line:match("(%d+) rows? affected")
      if count then
        row_count = tonumber(count)
        table.remove(output_lines, i)  -- Remove the footer line
      end
    end
    if row_count > 0 then
      return row_count
    end
  elseif normalized_type == "postgres" or normalized_type == "postgresql" then
    for i = #output_lines, 1, -1 do
      local line = output_lines[i]
      -- INSERT 0 5, UPDATE 5, DELETE 5
      local count = line:match("^%w+%s+%d*%s*(%d+)")
      if count then
        row_count = tonumber(count)
        table.remove(output_lines, i)  -- Remove the footer line
      end
    end
    if row_count > 0 then
      return row_count
    end
  end

  -- No "rows affected" found, count data rows (SELECT query)
  -- Skip first 2 lines (headers), count data rows, remove footer messages
  row_count = 0
  for i = #output_lines, 3, -1 do  -- Iterate backwards to safely remove
    local line = output_lines[i]
    if line:match("%(.*rows affected%)") or
       line:match("rows in set") or
       line:match("^%(.*rows%)") then
      table.remove(output_lines, i)  -- Remove footer line
    elseif line:match("%S") then
      row_count = row_count + 1
    end
  end

  return row_count
end

---Test database connection
---@param connection table Database connection
---@return boolean success True if connection successful
---@return string? error_msg Error message if connection failed
function M.test_connection(connection)
  local db_type = connection.type:lower():gsub("[%s%-_]", "")

  if db_type == "sqlite" then
    -- Test SQLite connection
    local db_path = vim.fn.expand(connection.path)
    if vim.fn.filereadable(db_path) == 0 then
      return false, "Database file not found: " .. db_path
    end

    -- Try to query the database
    local output = vim.fn.system({
      'sqlite3',
      db_path,
      'SELECT 1;'
    })

    if vim.v.shell_error ~= 0 then
      return false, "Failed to connect to SQLite database: " .. output
    end

    return true, nil

  elseif db_type == "sqlserver" or db_type == "mssql" then
    -- Test SQL Server connection
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
      table.insert(cmd, '-E') -- Windows authentication
    end

    -- Trust server certificate (for self-signed certs)
    -- Default to true for compatibility with most dev/test environments
    if connection.trust_server_certificate ~= false then
      table.insert(cmd, '-C')
    end

    table.insert(cmd, '-Q')
    table.insert(cmd, 'SELECT 1;')
    table.insert(cmd, '-h')
    table.insert(cmd, '-1') -- Remove headers

    local output = vim.fn.system(cmd)

    if vim.v.shell_error ~= 0 then
      return false, "Failed to connect to SQL Server: " .. output
    end

    return true, nil

  elseif db_type == "mysql" or db_type == "mariadb" then
    -- Test MySQL connection
    local cmd = {
      'mysql',
      '-h', connection.host or 'localhost',
      '-D', connection.database,
    }

    if connection.user then
      table.insert(cmd, '-u')
      table.insert(cmd, connection.user)
    end

    if connection.password then
      table.insert(cmd, '-p' .. connection.password)
    end

    table.insert(cmd, '-e')
    table.insert(cmd, 'SELECT 1;')

    local output = vim.fn.system(cmd)

    if vim.v.shell_error ~= 0 then
      return false, "Failed to connect to MySQL: " .. output
    end

    return true, nil

  elseif db_type == "postgres" or db_type == "postgresql" then
    -- Test PostgreSQL connection
    local cmd = {
      'psql',
      '-h', connection.host or 'localhost',
      '-d', connection.database,
    }

    -- Add port if specified
    if connection.port then
      table.insert(cmd, '-p')
      table.insert(cmd, tostring(connection.port))
    end

    if connection.user then
      table.insert(cmd, '-U')
      table.insert(cmd, connection.user)
    end

    -- Handle password
    if connection.password then
      -- Set PGPASSWORD environment variable
      vim.fn.setenv('PGPASSWORD', connection.password)
    else
      -- No password - add -w flag to prevent password prompt
      table.insert(cmd, '-w')
    end

    table.insert(cmd, '-c')
    table.insert(cmd, 'SELECT 1;')

    local output = vim.fn.system(cmd)

    -- Clear password from environment
    if connection.password then
      vim.fn.setenv('PGPASSWORD', nil)
    end

    if vim.v.shell_error ~= 0 then
      return false, "Failed to connect to PostgreSQL: " .. output
    end

    return true, nil
  end

  return false, "Unsupported database type: " .. connection.type
end

---Execute a query against a database connection
---@param connection table Database connection
---@param query string SQL query to execute
---@param query_bufnr number? Optional query buffer number (for associating results)
function M.execute(connection, query, query_bufnr)
  local db_type = connection.type:lower():gsub("[%s%-_]", "")

  if db_type == "sqlite" then
    M.execute_sqlite(connection, query, query_bufnr)
  elseif db_type == "sqlserver" or db_type == "mssql" then
    M.execute_sqlserver(connection, query, query_bufnr)
  elseif db_type == "mysql" or db_type == "mariadb" then
    M.execute_mysql(connection, query, query_bufnr)
  elseif db_type == "postgres" or db_type == "postgresql" then
    M.execute_postgres(connection, query, query_bufnr)
  else
    vim.notify("Database type '" .. connection.type .. "' not yet supported", vim.log.levels.ERROR)
  end
end

---Execute SQLite query using sqlite3 CLI
---@param connection table SQLite connection
---@param query string SQL query
---@param query_bufnr number? Optional query buffer number
function M.execute_sqlite(connection, query, query_bufnr)
  local output_lines = {}
  local start_time = vim.loop.hrtime()
  local affected_rows = nil

  -- Expand path
  local db_path = vim.fn.expand(connection.path)

  -- Check if database exists
  if vim.fn.filereadable(db_path) ~= 1 then
    vim.notify("Database file not found: " .. db_path, vim.log.levels.ERROR)
    return
  end

  vim.notify("Executing query...", vim.log.levels.INFO)

  -- Detect multiple top-level SELECT statements separated by semicolons
  -- This is a simple heuristic - it won't catch all cases but will catch the common ones
  local query_upper = query:upper()
  local semicolon_count = 0
  local has_select = false

  for statement in query_upper:gmatch("[^;]+") do
    local trimmed = statement:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed:match("^SELECT%s") then
      if has_select then
        semicolon_count = semicolon_count + 1
      end
      has_select = true
    end
  end

  if semicolon_count > 0 then
    vim.notify(
      "Warning: Multiple SELECT statements detected. Results may be garbled. Run queries separately for clean output.",
      vim.log.levels.WARN
    )
  end

  -- Detect if this is a DML statement (INSERT, UPDATE, DELETE)
  local query_trimmed = query_upper:gsub("^%s+", "")
  local is_dml = query_trimmed:match("^INSERT%s") or
                 query_trimmed:match("^UPDATE%s") or
                 query_trimmed:match("^DELETE%s")

  -- For DML statements, append SELECT changes() to get affected row count
  local exec_query = query
  if is_dml then
    exec_query = query .. "; SELECT changes();"
  end

  -- Pass query as command-line argument
  vim.fn.jobstart({
    'sqlite3',
    db_path,
    '-column',    -- Columnar output
    '-header',    -- Show column headers
    exec_query,   -- Query as argument (possibly with changes() appended)
  }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(output_lines, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.notify("Error: " .. line, vim.log.levels.ERROR)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      local end_time = vim.loop.hrtime()
      local duration = (end_time - start_time) / 1000000 -- Convert to milliseconds

      if exit_code == 0 then
        local row_count = 0

        -- For DML statements, extract the changes() result from the last line
        if is_dml and #output_lines > 0 then
          -- The last line should be the changes() result
          local last_line = output_lines[#output_lines]
          local changes = tonumber(last_line)
          if changes then
            row_count = changes
            -- Remove the changes() output lines (header + separator + value)
            -- Typically: "changes()", "----------", "200"
            if #output_lines >= 3 then
              table.remove(output_lines) -- Remove value
              table.remove(output_lines) -- Remove separator
              table.remove(output_lines) -- Remove header
            end
          end
        else
          -- For SELECT queries, count rows using unified logic
          row_count = count_rows(output_lines, connection.type)
        end

        -- Detect query type for better messaging
        local query_type = nil
        if query_upper:match("^CREATE%s+TABLE") then
          query_type = "CREATE_TABLE"
        elseif query_upper:match("^DROP%s+TABLE") then
          query_type = "DROP_TABLE"
        elseif query_upper:match("^ALTER%s+TABLE") then
          query_type = "ALTER_TABLE"
        elseif query_upper:match("^INSERT%s") then
          query_type = "INSERT"
        elseif query_upper:match("^UPDATE%s") then
          query_type = "UPDATE"
        elseif query_upper:match("^DELETE%s") then
          query_type = "DELETE"
        end

        -- Build metadata
        local metadata = {
          execution_time = duration,
          row_count = row_count,
          db_type = connection.type,
          timestamp = os.date("%Y-%m-%d %H:%M:%S"),
          connection_name = connection.name,
          query_type = query_type,
        }

        -- Parse and format results for consistent display (if enabled)
        local config = require("enhance.config")
        local formatted_lines = output_lines
        local parsed_result = nil
        if config.get("format_results") then
          local parser = require("enhance.parser")
          local formatter = require("enhance.formatter")
          parsed_result = parser.parse(output_lines, connection.type)
          formatted_lines = formatter.format(parsed_result)
          -- Add parsed result to metadata for JSON detection
          metadata.parsed_result = parsed_result
        end

        -- Display results with metadata (no footer added here)
        require("enhance.results").display(formatted_lines, connection, query_bufnr, metadata)

        -- Auto-refresh explorer if this was a DDL statement (CREATE/DROP/ALTER TABLE)
        local query_upper = query:upper():gsub("^%s+", "")
        if query_upper:match("^CREATE%s+TABLE") or
           query_upper:match("^DROP%s+TABLE") or
           query_upper:match("^ALTER%s+TABLE") then
          -- Refresh explorer to show updated table list
          vim.schedule(function()
            local explorer = require("enhance.explorer")
            if explorer.is_open() then
              explorer.refresh()
            end
          end)
        end
      else
        vim.notify("Query execution failed (exit code: " .. exit_code .. ")", vim.log.levels.ERROR)
      end
    end,
  })
end

---Execute SQL Server query using sqlcmd CLI
---@param connection table SQL Server connection
---@param query string SQL query
---@param query_bufnr number? Optional query buffer number
function M.execute_sqlserver(connection, query, query_bufnr)
  local output_lines = {}
  local start_time = vim.loop.hrtime()

  vim.notify("Executing SQL Server query...", vim.log.levels.INFO)

  -- Build connection string
  local cmd = { 'sqlcmd' }

  if connection.server or connection.host then
    table.insert(cmd, '-S')
    table.insert(cmd, connection.server or connection.host)
  end

  if connection.database then
    table.insert(cmd, '-d')
    table.insert(cmd, connection.database)
  end

  if connection.user or connection.username then
    table.insert(cmd, '-U')
    table.insert(cmd, connection.user or connection.username)
  end

  if connection.password then
    table.insert(cmd, '-P')
    table.insert(cmd, connection.password)
  end

  -- Use Windows Authentication if no user/password
  if not connection.user and not connection.username and not connection.password then
    table.insert(cmd, '-E')
  end

  -- Trust server certificate (for self-signed certs)
  -- Default to true for compatibility with most dev/test environments
  if connection.trust_server_certificate ~= false then
    table.insert(cmd, '-C')
  end

  -- Output formatting
  table.insert(cmd, '-s')
  table.insert(cmd, '|') -- Column separator
  table.insert(cmd, '-W') -- Remove trailing spaces
  table.insert(cmd, '-Q')
  table.insert(cmd, query)

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(output_lines, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.notify("Error: " .. line, vim.log.levels.ERROR)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      local end_time = vim.loop.hrtime()
      local duration = (end_time - start_time) / 1000000

      if exit_code == 0 then
        -- Count rows using unified logic
        local row_count = count_rows(output_lines, connection.type)

        -- Build metadata
        local metadata = {
          execution_time = duration,
          row_count = row_count,
          db_type = connection.type,
          timestamp = os.date("%Y-%m-%d %H:%M:%S"),
          connection_name = connection.name,
        }

        -- Parse and format results for consistent display (if enabled)
        local config = require("enhance.config")
        local formatted_lines = output_lines
        if config.get("format_results") then
          local parser = require("enhance.parser")
          local formatter = require("enhance.formatter")
          local parsed = parser.parse(output_lines, connection.type)
          formatted_lines = formatter.format(parsed)
        end

        -- Display results with metadata (no footer added here)
        require("enhance.results").display(formatted_lines, connection, query_bufnr, metadata)

        -- Auto-refresh explorer if this was a DDL statement (CREATE/DROP/ALTER TABLE)
        local query_upper = query:upper():gsub("^%s+", "")
        if query_upper:match("^CREATE%s+TABLE") or
           query_upper:match("^DROP%s+TABLE") or
           query_upper:match("^ALTER%s+TABLE") then
          -- Refresh explorer to show updated table list
          vim.schedule(function()
            local explorer = require("enhance.explorer")
            if explorer.is_open() then
              explorer.refresh()
            end
          end)
        end
      else
        vim.notify("Query execution failed (exit code: " .. exit_code .. ")", vim.log.levels.ERROR)
      end
    end,
  })
end

---Execute MySQL query using mysql CLI
---@param connection table MySQL connection
---@param query string SQL query
---@param query_bufnr number? Optional query buffer number
function M.execute_mysql(connection, query, query_bufnr)
  local output_lines = {}
  local start_time = vim.loop.hrtime()

  vim.notify("Executing MySQL query...", vim.log.levels.INFO)

  local cmd = { 'mysql' }

  if connection.host then
    table.insert(cmd, '-h')
    table.insert(cmd, connection.host)
  end

  if connection.port then
    table.insert(cmd, '-P')
    table.insert(cmd, tostring(connection.port))
  end

  if connection.user or connection.username then
    table.insert(cmd, '-u')
    table.insert(cmd, connection.user or connection.username)
  end

  if connection.password then
    table.insert(cmd, '-p' .. connection.password)
  end

  if connection.database then
    table.insert(cmd, connection.database)
  end

  table.insert(cmd, '-e')
  table.insert(cmd, query)

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(output_lines, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" and not line:match("^mysql: %[Warning%]") then
            vim.notify("Error: " .. line, vim.log.levels.ERROR)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      local end_time = vim.loop.hrtime()
      local duration = (end_time - start_time) / 1000000

      if exit_code == 0 then
        -- Count rows using unified logic
        local row_count = count_rows(output_lines, connection.type)

        -- Build metadata
        local metadata = {
          execution_time = duration,
          row_count = row_count,
          db_type = connection.type,
          timestamp = os.date("%Y-%m-%d %H:%M:%S"),
          connection_name = connection.name,
        }

        -- Parse and format results for consistent display (if enabled)
        local config = require("enhance.config")
        local formatted_lines = output_lines
        local parsed_result = nil
        if config.get("format_results") then
          local parser = require("enhance.parser")
          local formatter = require("enhance.formatter")
          parsed_result = parser.parse(output_lines, connection.type)
          formatted_lines = formatter.format(parsed_result)
          -- Add parsed result to metadata for JSON detection
          metadata.parsed_result = parsed_result
        end

        -- Display results with metadata (no footer added here)
        require("enhance.results").display(formatted_lines, connection, query_bufnr, metadata)

        -- Auto-refresh explorer if this was a DDL statement (CREATE/DROP/ALTER TABLE)
        local query_upper = query:upper():gsub("^%s+", "")
        if query_upper:match("^CREATE%s+TABLE") or
           query_upper:match("^DROP%s+TABLE") or
           query_upper:match("^ALTER%s+TABLE") then
          -- Refresh explorer to show updated table list
          vim.schedule(function()
            local explorer = require("enhance.explorer")
            if explorer.is_open() then
              explorer.refresh()
            end
          end)
        end
      else
        vim.notify("Query execution failed (exit code: " .. exit_code .. ")", vim.log.levels.ERROR)
      end
    end,
  })
end

---Execute PostgreSQL query using psql CLI
---@param connection table PostgreSQL connection
---@param query string SQL query
---@param query_bufnr number? Optional query buffer number
function M.execute_postgres(connection, query, query_bufnr)
  local output_lines = {}
  local start_time = vim.loop.hrtime()

  vim.notify("Executing PostgreSQL query...", vim.log.levels.INFO)

  -- Build command with individual flags (like test_connection does)
  local cmd = {
    'psql',
    '-h', connection.host or 'localhost',
    '-d', connection.database,
  }

  -- Add port if specified
  if connection.port then
    table.insert(cmd, '-p')
    table.insert(cmd, tostring(connection.port))
  end

  -- Add user if specified
  if connection.user or connection.username then
    table.insert(cmd, '-U')
    table.insert(cmd, connection.user or connection.username)
  end

  -- Handle password via environment variable
  if connection.password then
    vim.fn.setenv('PGPASSWORD', connection.password)
  else
    -- No password - add -w flag to prevent password prompt
    table.insert(cmd, '-w')
  end

  -- Add query
  table.insert(cmd, '-c')
  table.insert(cmd, query)

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(output_lines, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.notify("Error: " .. line, vim.log.levels.ERROR)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      local end_time = vim.loop.hrtime()
      local duration = (end_time - start_time) / 1000000

      -- Clear password from environment
      if connection.password then
        vim.fn.setenv('PGPASSWORD', nil)
      end

      if exit_code == 0 then
        -- Count rows using unified logic
        local row_count = count_rows(output_lines, connection.type)

        -- Build metadata
        local metadata = {
          execution_time = duration,
          row_count = row_count,
          db_type = connection.type,
          timestamp = os.date("%Y-%m-%d %H:%M:%S"),
          connection_name = connection.name,
        }

        -- Parse and format results for consistent display (if enabled)
        local config = require("enhance.config")
        local formatted_lines = output_lines
        local parsed_result = nil
        if config.get("format_results") then
          local parser = require("enhance.parser")
          local formatter = require("enhance.formatter")
          parsed_result = parser.parse(output_lines, connection.type)
          formatted_lines = formatter.format(parsed_result)
          -- Add parsed result to metadata for JSON detection
          metadata.parsed_result = parsed_result
        end

        -- Display results with metadata (no footer added here)
        require("enhance.results").display(formatted_lines, connection, query_bufnr, metadata)

        -- Auto-refresh explorer if this was a DDL statement (CREATE/DROP/ALTER TABLE)
        local query_upper = query:upper():gsub("^%s+", "")
        if query_upper:match("^CREATE%s+TABLE") or
           query_upper:match("^DROP%s+TABLE") or
           query_upper:match("^ALTER%s+TABLE") then
          -- Refresh explorer to show updated table list
          vim.schedule(function()
            local explorer = require("enhance.explorer")
            if explorer.is_open() then
              explorer.refresh()
            end
          end)
        end
      else
        vim.notify("Query execution failed (exit code: " .. exit_code .. ")", vim.log.levels.ERROR)
      end
    end,
  })
end

-- Expose for testing
M._execute_sqlite = M.execute_sqlite
M._execute_sqlserver = M.execute_sqlserver
M._execute_mysql = M.execute_mysql
M._execute_postgres = M.execute_postgres

return M

