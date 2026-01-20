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
    -- Count total rows from all "(X rows affected)" markers
    -- DO NOT remove these lines - parser needs them to detect multiple result sets
    for _, line in ipairs(output_lines) do
      local count = line:match("%((%d+) rows? affected%)")
      if count then
        row_count = row_count + tonumber(count)
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

---Execute a single SQLite statement and return parsed result
---@param connection table SQLite connection
---@param statement_text string Single SQL statement
---@return table|nil Parsed result or nil on error
---@return string|nil Error message if execution failed
---@return number Execution time in milliseconds
---@return number Row count
local function execute_single_sqlite_statement(connection, statement_text)
  local output_lines = {}
  local error_lines = {}
  local start_time = vim.loop.hrtime()

  -- Expand path
  local db_path = vim.fn.expand(connection.path)

  -- Detect if this is a DML statement (INSERT, UPDATE, DELETE)
  local query_upper = statement_text:upper()
  local query_trimmed = query_upper:gsub("^%s+", "")
  local is_dml = query_trimmed:match("^INSERT%s") or
                 query_trimmed:match("^UPDATE%s") or
                 query_trimmed:match("^DELETE%s")

  -- For DML statements, append SELECT changes() to get affected row count
  local exec_query = statement_text
  if is_dml then
    exec_query = statement_text .. "; SELECT changes();"
  end

  -- Execute synchronously using vim.fn.system
  local cmd = string.format("sqlite3 %s -column -header %s",
    vim.fn.shellescape(db_path),
    vim.fn.shellescape(exec_query))

  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  local end_time = vim.loop.hrtime()
  local duration = (end_time - start_time) / 1000000 -- Convert to milliseconds

  -- Split output into lines
  for line in output:gmatch("[^\r\n]+") do
    if line ~= "" then
      table.insert(output_lines, line)
    end
  end

  if exit_code ~= 0 then
    return nil, output, duration, 0
  end

  local row_count = 0

  -- For DML statements, extract the changes() result from the last line
  if is_dml and #output_lines > 0 then
    local last_line = output_lines[#output_lines]
    local changes = tonumber(last_line)
    if changes then
      row_count = changes
      -- Remove the changes() output lines (header + separator + value)
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

  -- Parse the output
  local parser = require("enhance.parser")
  local parsed_result = parser.parse(output_lines, connection.type)

  return parsed_result, nil, duration, row_count
end

---Execute SQLite statements individually (de-batched)
---@param connection table SQLite connection
---@param groups table[] Execution groups from classifier
---@param query_bufnr number? Optional query buffer number
local function execute_debatch_sqlite(connection, groups, query_bufnr)
  local all_statement_results = {}
  local total_duration = 0
  local had_error = false
  local error_message = nil

  -- Process each group
  for _, group in ipairs(groups) do
    if group.type == "individual" then
      -- Execute each statement individually
      for _, stmt in ipairs(group.statements) do
        local parsed_result, err, duration, row_count = execute_single_sqlite_statement(connection, stmt.text)
        total_duration = total_duration + duration

        if err then
          -- Create error result
          local result = {
            type = stmt.type,
            query_text = stmt.text,
            rows = 0,
            elapsed = duration,
            db_type = connection.type,
            db_name = connection.name,
            executed_on = os.date("%Y-%m-%d %H:%M:%S"),
            result_table = nil,
            message = "ERROR: " .. err,
            error = true,
          }
          table.insert(all_statement_results, result)
          had_error = true
          error_message = err
          break -- Stop on first error
        else
          -- Create success result
          local result = {
            type = stmt.type,
            query_text = stmt.text,
            rows = row_count,
            elapsed = duration,
            db_type = connection.type,
            db_name = connection.name,
            executed_on = os.date("%Y-%m-%d %H:%M:%S"),
          }

          -- Add result_table for SELECT, message for DML/DDL
          if stmt.type == "SELECT" or stmt.type == "UNKNOWN" then
            result.result_table = {
              headers = parsed_result.headers,
              rows = parsed_result.rows,
            }
            result.message = nil
          elseif stmt.type == "INSERT" or stmt.type == "UPDATE" or stmt.type == "DELETE" then
            result.result_table = nil
            local statement_matcher = require("enhance.statement_matcher")
            result.message = statement_matcher._generate_dml_message(stmt.type, row_count)
          elseif stmt.type == "CREATE" or stmt.type == "DROP" or stmt.type == "ALTER" then
            result.result_table = nil
            local statement_matcher = require("enhance.statement_matcher")
            -- Detect query type for DDL
            local query_type = nil
            local upper = stmt.text:upper()
            if upper:match("^CREATE%s+TABLE") then
              query_type = "CREATE_TABLE"
            elseif upper:match("^DROP%s+TABLE") then
              query_type = "DROP_TABLE"
            elseif upper:match("^ALTER%s+TABLE") then
              query_type = "ALTER_TABLE"
            end
            result.message = statement_matcher._generate_ddl_message(query_type)
          end

          table.insert(all_statement_results, result)
        end
      end

      if had_error then
        break -- Stop processing groups on error
      end
    else
      -- Batch group - execute together (future implementation)
      -- For now, execute individually
      for _, stmt in ipairs(group.statements) do
        local parsed_result, err, duration, row_count = execute_single_sqlite_statement(connection, stmt.text)
        total_duration = total_duration + duration

        if err then
          had_error = true
          error_message = err
          break
        end

        -- Create result (batched statements don't show individual elapsed time)
        local result = {
          type = stmt.type,
          query_text = stmt.text,
          rows = stmt.type == "SELECT" and #parsed_result.rows or row_count,
          elapsed = 0,  -- Batched statements: no individual time (only total shown in status line)
          db_type = connection.type,
          db_name = connection.name,
          executed_on = os.date("%Y-%m-%d %H:%M:%S"),
        }

        if stmt.type == "SELECT" or stmt.type == "UNKNOWN" then
          result.result_table = {
            headers = parsed_result.headers,
            rows = parsed_result.rows,
          }
        end

        table.insert(all_statement_results, result)
      end

      if had_error then
        break
      end
    end
  end

  -- Format and display results
  if had_error then
    local error_display = {
      "Query Execution Failed",
      "",
      error_message or "Unknown error",
    }
    require("enhance.results").display_message(error_display, connection, query_bufnr)
    vim.notify("Query execution failed", vim.log.levels.ERROR)
  else
    local formatter = require("enhance.formatter")
    local formatted_lines, total_table_rows = formatter.format_multiple_statements(all_statement_results)

    -- Build metadata
    local metadata = {
      execution_time = total_duration,
      row_count = total_table_rows or 0,
      db_type = connection.type,
      timestamp = os.date("%Y-%m-%d %H:%M:%S"),
      connection_name = connection.name,
      statement_count = #all_statement_results,
      total_table_rows = total_table_rows,
    }

    require("enhance.results").display(formatted_lines, connection, query_bufnr, metadata)
    vim.notify("Query executed successfully", vim.log.levels.INFO)
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

  -- Detect statements BEFORE execution (Phase 1)
  local statement_detector = require("enhance.statement_detector")
  local detected_statements = statement_detector.detect_statements(query)

  -- Classify execution strategy (Phase 2)
  local statement_classifier = require("enhance.statement_classifier")
  local classification = statement_classifier.classify_for_execution(detected_statements)

  -- Route to appropriate execution path
  if classification.execution_mode == "debatch" then
    -- Use new de-batch execution
    execute_debatch_sqlite(connection, classification.groups, query_bufnr)
    return
  end

  -- Continue with existing batch execution for batch mode

  -- Detect if this is a DML statement (INSERT, UPDATE, DELETE)
  local query_upper = query:upper()
  local query_trimmed = query_upper:gsub("^%s+", "")
  local is_dml = query_trimmed:match("^INSERT%s") or
                 query_trimmed:match("^UPDATE%s") or
                 query_trimmed:match("^DELETE%s")

  -- For DML statements, append SELECT changes() to get affected row count
  local exec_query = query
  if is_dml then
    exec_query = query .. "; SELECT changes();"
  end

  -- Collect errors for display in results window
  local error_lines = {}

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
            table.insert(error_lines, line)
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

          -- Phase 2: Parse output (supports multiple result sets)
          parsed_result = parser.parse(output_lines, connection.type)

          -- Phase 3 & 4: Match statements to output and format
          if #detected_statements > 0 then
            local statement_matcher = require("enhance.statement_matcher")
            local matched_results = statement_matcher.match_statements(
              detected_statements,
              parsed_result,
              metadata
            )
            local total_table_rows
            formatted_lines, total_table_rows = formatter.format_multiple_statements(matched_results)

            -- Update metadata for multiple statements
            -- Use matched_results count (filters out transaction control statements)
            metadata.statement_count = #matched_results
            metadata.total_table_rows = total_table_rows
          else
            -- Fallback to old format for backward compatibility
            formatted_lines = formatter.format(parsed_result)
          end

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
        -- Display error in results window
        local error_display = {
          "Query Execution Failed",
        }

        if #error_lines > 0 then
          for _, err_line in ipairs(error_lines) do
            table.insert(error_display, err_line)
          end
        else
          table.insert(error_display, "Exit code: " .. exit_code)
        end

        -- Also show notification for immediate feedback
        vim.notify("Query execution failed", vim.log.levels.ERROR)

        -- Display error in results window with cursor movement
        require("enhance.results").display(error_display, connection, query_bufnr, {
          execution_time = (vim.loop.hrtime() - start_time) / 1000000,
          db_type = connection.type,
          timestamp = os.date("%Y-%m-%d %H:%M:%S"),
          connection_name = connection.name,
          is_error = true,  -- Flag to apply error highlighting
        })
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
  table.insert(cmd, '-y')
  table.insert(cmd, '8000') -- Max variable-type column width (for NVARCHAR/VARCHAR)
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

        -- Detect SQL statements in the query
        local statement_detector = require("enhance.statement_detector")
        local detected_statements = statement_detector.detect_statements(query)

        -- Parse and format results for consistent display (if enabled)
        local config = require("enhance.config")
        local formatted_lines = output_lines
        local parsed_result = nil
        if config.get("format_results") then
          local parser = require("enhance.parser")
          local formatter = require("enhance.formatter")

          -- Phase 2: Parse output (supports multiple result sets)
          parsed_result = parser.parse(output_lines, connection.type)

          -- Phase 3 & 4: Match statements to output and format
          if #detected_statements > 0 then
            local statement_matcher = require("enhance.statement_matcher")
            local matched_results = statement_matcher.match_statements(
              detected_statements,
              parsed_result,
              metadata
            )
            local total_table_rows
            formatted_lines, total_table_rows = formatter.format_multiple_statements(matched_results)

            -- Update metadata for multiple statements
            -- Use matched_results count (filters out transaction control statements)
            metadata.statement_count = #matched_results
            metadata.total_table_rows = total_table_rows
          else
            -- Fallback to old format for backward compatibility
            formatted_lines = formatter.format(parsed_result)
          end

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
M._execute_single_sqlite_statement = execute_single_sqlite_statement
M._execute_debatch_sqlite = execute_debatch_sqlite

return M

