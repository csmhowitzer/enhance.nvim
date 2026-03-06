-- enhance.nvim - Query executor
-- Executes database queries using CLI tools (sqlite3, psql, etc.)

local M = {}

local sqlite_adapter    = require("enhance.db.sqlite")
local sqlserver_adapter = require("enhance.db.sqlserver")
local mysql_adapter     = require("enhance.db.mysql")
local postgres_adapter  = require("enhance.db.postgres")

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

---Build a sqlcmd command array (delegates to sqlserver adapter)
---@param connection table SQL Server connection
---@param opts table SqlcmdOptions
---@return string[] Command array
local function build_sqlcmd_cmd(connection, opts)
  return sqlserver_adapter.build_cmd(connection, opts)
end

---Test database connection
---@param connection table Database connection
---@return boolean success True if connection successful
---@return string? error_msg Error message if connection failed
function M.test_connection(connection)
  local db_type = connection.type:lower():gsub("[%s%-_]", "")

  if db_type == "sqlite" then
    return sqlite_adapter.test_connection(connection)

  elseif db_type == "sqlserver" or db_type == "mssql" then
    return sqlserver_adapter.test_connection(connection)

  elseif db_type == "mysql" or db_type == "mariadb" then
    return mysql_adapter.test_connection(connection)

  elseif db_type == "postgres" or db_type == "postgresql" then
    return postgres_adapter.test_connection(connection)
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

---Execute a single SQLite statement and return parsed result (delegates to sqlite adapter)
---@param connection table SQLite connection
---@param statement_text string Single SQL statement
---@return table|nil Parsed result or nil on error
---@return string|nil Error message if execution failed
---@return number Execution time in milliseconds
---@return number Row count
local function execute_single_sqlite_statement(connection, statement_text)
  return sqlite_adapter.execute_single(connection, statement_text)
end

---Build a statement result object with a consistent structure
---@param stmt table Statement object with .type and .text fields
---@param connection table Database connection
---@param duration number Execution time in milliseconds
---@param row_count number Rows affected or returned
---@param parsed_result table|nil Parsed output (non-nil for successful SELECT)
---@param err string|nil Error message if execution failed
---@return table Statement result object
local function make_statement_result(stmt, connection, duration, row_count, parsed_result, err)
  local result = {
    type         = stmt.type,
    query_text   = stmt.text,
    elapsed      = duration,
    db_type      = connection.type,
    db_name      = connection.database or connection.name,
    executed_on  = os.date("%Y-%m-%d %H:%M:%S"),
  }

  if err then
    result.rows         = 0
    result.result_table = nil
    result.message      = "ERROR: " .. err
    result.error        = true
    return result
  end

  result.rows = row_count

  if stmt.type == "SELECT" or stmt.type == "UNKNOWN" then
    result.result_table = {
      headers = parsed_result and parsed_result.headers or {},
      rows    = parsed_result and parsed_result.rows    or {},
    }
    result.message = nil
  elseif stmt.type == "INSERT" or stmt.type == "UPDATE" or stmt.type == "DELETE" then
    result.result_table = nil
    local statement_matcher = require("enhance.statement_matcher")
    result.message = statement_matcher._generate_dml_message(stmt.type, row_count)
  elseif stmt.type == "CREATE" or stmt.type == "DROP" or stmt.type == "ALTER" then
    result.result_table = nil
    local statement_matcher = require("enhance.statement_matcher")
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

  return result
end

---Execute statements individually (de-batched) using a DB-specific executor
---Shared implementation for all database types that support debatch mode.
---@param connection table Database connection
---@param groups table[] Execution groups from the statement classifier
---@param query_bufnr number? Optional query buffer number
---@param execute_single_fn function DB-specific single-statement executor
---  Signature: fn(connection, stmt_text) -> parsed_result, err, duration, row_count
local function execute_debatch(connection, groups, query_bufnr, execute_single_fn)
  local all_statement_results = {}
  local total_duration = 0
  local had_error = false

  for _, group in ipairs(groups) do
    for _, stmt in ipairs(group.statements) do
      local parsed_result, err, duration, row_count = execute_single_fn(connection, stmt.text)
      total_duration = total_duration + duration

      local result = make_statement_result(stmt, connection, duration, row_count, parsed_result, err)
      table.insert(all_statement_results, result)

      if err then
        had_error = true
        break
      end
    end

    if had_error then break end
  end

  local formatter = require("enhance.formatter")
  local formatted_lines, total_table_rows = formatter.format_multiple_statements(all_statement_results)

  -- Fallback: if the error result wasn't captured by the formatter, append a notice
  if had_error then
    local last = all_statement_results[#all_statement_results]
    if not (last and last.error) then
      table.insert(formatted_lines, "")
      table.insert(formatted_lines, "Query Execution Failed")
      table.insert(formatted_lines, "(Remaining statements not executed)")
    end
  end

  local metadata = {
    execution_time   = total_duration,
    row_count        = total_table_rows or 0,
    db_type          = connection.type,
    timestamp        = os.date("%Y-%m-%d %H:%M:%S"),
    connection_name  = connection.name,
    statement_count  = #all_statement_results,
    total_table_rows = total_table_rows,
    is_error         = had_error,
    statement_results = all_statement_results,
  }

  require("enhance.results").display(formatted_lines, connection, query_bufnr, metadata)

  if had_error then
    vim.notify("Query execution failed with partial results", vim.log.levels.WARN)
  else
    vim.notify("Query executed successfully", vim.log.levels.INFO)
  end
end

---Execute SQLite statements individually (de-batched)
---@param connection table SQLite connection
---@param groups table[] Execution groups from classifier
---@param query_bufnr number? Optional query buffer number
local function execute_debatch_sqlite(connection, groups, query_bufnr)
  execute_debatch(connection, groups, query_bufnr, execute_single_sqlite_statement)
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

  local query_upper = query:upper()
  local is_dml, exec_query = sqlite_adapter.prepare_query(query)

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

---Execute a single SQL Server statement (delegates to sqlserver adapter)
---@param connection table SQL Server connection
---@param statement_text string Single SQL statement
---@return table|nil parsed_result
---@return string|nil error_msg
---@return number duration milliseconds
---@return number row_count
local function execute_single_sqlserver_statement(connection, statement_text)
  return sqlserver_adapter.execute_single(connection, statement_text)
end

---Execute SQL Server statements individually (de-batched)
---@param connection table SQL Server connection
---@param groups table[] Execution groups from classifier
---@param query_bufnr number? Optional query buffer number
local function execute_debatch_sqlserver(connection, groups, query_bufnr)
  execute_debatch(connection, groups, query_bufnr, M._execute_single_sqlserver_statement)
end

---Parse SQL Server batch output that contains errors and display results
---Separates any successful result sets that appeared before the error.
---@param output_lines string[] Raw output lines from sqlcmd
---@param query string Original SQL query (used for query_text on pure-error results)
---@param connection table SQL Server connection
---@param duration number Total execution time in milliseconds
---@param query_bufnr number? Optional query buffer number
local function parse_batch_error_output(output_lines, query, connection, duration, query_bufnr)
  -- Collect the error message block (everything from the first "Msg X, Level Y" onward)
  local error_lines_text = {}
  local in_error = false
  for _, line in ipairs(output_lines) do
    if line:match("Msg %d+, Level %d+") then in_error = true end
    if in_error then table.insert(error_lines_text, line) end
  end

  -- Parse full output — may contain partial result sets before the error
  local parsed_result = require("enhance.parser").parse(output_lines, connection.type)

  -- Normalise to multiple_results format for consistent processing
  local has_successful_results = false
  if parsed_result and parsed_result.multiple_results and #parsed_result.result_sets > 0 then
    has_successful_results = true
  elseif parsed_result and parsed_result.headers and #parsed_result.headers > 0
      and parsed_result.rows and #parsed_result.rows > 0 then
    has_successful_results = true
    parsed_result = {
      multiple_results = true,
      result_sets = { { headers = parsed_result.headers, rows = parsed_result.rows,
                         metadata = parsed_result.metadata or {} } },
      metadata = parsed_result.metadata or { db_type = connection.type },
    }
  end

  local all_statement_results = {}

  if has_successful_results then
    -- One synthetic result object per successful result set
    for _, result_set in ipairs(parsed_result.result_sets) do
      table.insert(all_statement_results, {
        type        = "SELECT",
        query_text  = "",
        rows        = #result_set.rows,
        elapsed     = 0,  -- batch mode: no per-statement timing
        db_type     = connection.type,
        db_name     = connection.database or connection.name,
        executed_on = os.date("%Y-%m-%d %H:%M:%S"),
        result_table = { headers = result_set.headers, rows = result_set.rows },
      })
    end
  end

  -- Append the error result
  table.insert(all_statement_results, {
    type        = "SELECT",
    query_text  = has_successful_results and "" or query,
    rows        = 0,
    elapsed     = has_successful_results and 0 or duration,
    db_type     = connection.type,
    db_name     = connection.database or connection.name,
    executed_on = os.date("%Y-%m-%d %H:%M:%S"),
    result_table = nil,
    message     = "ERROR: " .. table.concat(error_lines_text, "\n"),
    error       = true,
  })

  local formatter = require("enhance.formatter")
  local formatted_lines, total_table_rows = formatter.format_multiple_statements(all_statement_results)

  local metadata = {
    execution_time    = duration,
    row_count         = total_table_rows or 0,
    db_type           = connection.type,
    timestamp         = os.date("%Y-%m-%d %H:%M:%S"),
    connection_name   = connection.name,
    statement_count   = #all_statement_results,
    total_table_rows  = total_table_rows,
    is_error          = true,
    statement_results = all_statement_results,
  }

  vim.notify("Query execution failed", vim.log.levels.ERROR)
  require("enhance.results").display(formatted_lines, connection, query_bufnr, metadata)
end

---Execute SQL Server query using sqlcmd CLI
---@param connection table SQL Server connection
---@param query string SQL query
---@param query_bufnr number? Optional query buffer number
function M.execute_sqlserver(connection, query, query_bufnr)
  vim.notify("Executing SQL Server query...", vim.log.levels.INFO)

  -- Detect statements BEFORE execution (Phase 1)
  local statement_detector = require("enhance.statement_detector")
  local detected_statements = statement_detector.detect_statements(query)

  -- Classify execution strategy (Phase 2)
  local statement_classifier = require("enhance.statement_classifier")
  local classification = statement_classifier.classify_for_execution(detected_statements)

  -- Route to appropriate execution path
  if classification.execution_mode == "debatch" then
    -- Use new de-batch execution
    execute_debatch_sqlserver(connection, classification.groups, query_bufnr)
    return
  end

  -- Continue with existing batch execution for batch mode
  local output_lines = {}
  local error_lines = {}
  local start_time = vim.loop.hrtime()

  local cmd = build_sqlcmd_cmd(connection, { query = query })

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
            table.insert(error_lines, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      local end_time = vim.loop.hrtime()
      local duration = (end_time - start_time) / 1000000

      -- Check for SQL errors in output (sqlcmd returns 0 even for SQL errors)
      -- SQL Server error format: "Msg 208, Level 16, State 1, ..."
      local has_sql_error = false
      for _, line in ipairs(output_lines) do
        if line:match("Msg %d+, Level %d+") then
          has_sql_error = true
          break
        end
      end

      if has_sql_error then
        parse_batch_error_output(output_lines, query, connection, duration, query_bufnr)
        return
      end

      if exit_code ~= 0 then
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

        -- Display error in results window
        require("enhance.results").display_message(error_display, true)
        return
      end

      -- Success case
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

  local cmd = mysql_adapter.build_cmd(connection, { query = query })

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

  -- Set PGPASSWORD before building cmd (adapter.build_cmd omits -w when password present)
  if connection.password then
    vim.fn.setenv('PGPASSWORD', connection.password)
  end

  local cmd = postgres_adapter.build_cmd(connection, { query = query })

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
        -- Count rows using unified logic (this also removes DML footer lines)
        local row_count = count_rows(output_lines, connection.type)

        -- Detect if this is a DML statement (INSERT/UPDATE/DELETE)
        -- If row_count > 0 but output_lines is empty, it was a DML statement
        local query_upper = query:upper():gsub("^%s+", "")
        local is_insert = query_upper:match("^INSERT%s")
        local is_update = query_upper:match("^UPDATE%s")
        local is_delete = query_upper:match("^DELETE%s")
        local is_dml = is_insert or is_update or is_delete

        -- If DML statement with affected rows, add success message
        if is_dml and row_count > 0 and #output_lines == 0 then
          local action = is_insert and "inserted" or (is_update and "updated" or "deleted")
          local message = string.format("✓ %d row%s %s", row_count, row_count == 1 and "" or "s", action)
          table.insert(output_lines, message)
        end

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
M._execute_single_sqlserver_statement = execute_single_sqlserver_statement
M._execute_debatch_sqlserver = execute_debatch_sqlserver
M._prepare_sqlite_query = sqlite_adapter.prepare_query
M._build_sqlcmd_cmd = build_sqlcmd_cmd
M._parse_batch_error_output = parse_batch_error_output

return M

