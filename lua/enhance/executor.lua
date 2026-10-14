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

  if stmt.type == "SELECT" or stmt.type == "UNKNOWN" or stmt.type == 'PRAGMA'
    or stmt.type == 'SHOW' or stmt.type == 'DESCRIBE' or stmt.type == 'EXPLAIN' then
    result.result_table = {
      headers = parsed_result and parsed_result.headers or {},
      rows    = parsed_result and parsed_result.rows    or {},
      column_types = parsed_result and parsed_result.column_types,
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
    local texts = {}
    for _, stmt in ipairs(group.statements) do texts[#texts + 1] = stmt.text end
    -- Put separators on their own lines so a trailing -- comment cannot swallow them.
    local sql = table.concat(texts, '\n;\n')
    local parsed_result, err, duration, row_count = execute_single_fn(connection, sql)
    total_duration = total_duration + duration
    if group.type == 'batch' and not err then
      local tables = parsed_result and parsed_result.result_sets or {}
      if #tables == 0 and parsed_result and parsed_result.headers then tables = { parsed_result } end
      for index, result_table in ipairs(tables) do
        local stmt = group.statements[index] or { type = 'SELECT', text = sql }
        table.insert(all_statement_results,
          make_statement_result(stmt, connection, index == 1 and duration or 0,
            #result_table.rows, result_table, nil))
      end
    else
      local stmt = group.statements[1]
      local result = make_statement_result(stmt, connection, duration, row_count, parsed_result, err)
      table.insert(all_statement_results, result)
      if err then had_error = true end
    end

    if had_error then break end
  end

  local formatter = require("enhance.formatter")
  local formatted_lines, total_table_rows, result_rows = formatter.format_multiple_statements(all_statement_results)

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
    result_rows     = result_rows,
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
  local timer, finished, timed_out = nil, false, false
  local job = vim.fn.jobstart({
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
      finished = true
      if timer and not timer:is_closing() then timer:stop(); timer:close() end
      local end_time = vim.loop.hrtime()
      local duration = (end_time - start_time) / 1000000 -- Convert to milliseconds

      if exit_code == 0 and not timed_out then
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
            formatted_lines, total_table_rows, metadata.result_rows = formatter.format_multiple_statements(matched_results)
            metadata.statement_results = matched_results

            -- Update metadata for multiple statements
            -- Use matched_results count (filters out transaction control statements)
            metadata.statement_count = #matched_results
            metadata.total_table_rows = total_table_rows
          else
            -- Fallback to old format for backward compatibility
            formatted_lines, metadata.result_rows = formatter.format(parsed_result)
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

        if timed_out then
          table.insert(error_display, 'SQLite query timed out after '
            .. require('enhance.db.query_timeout').command_seconds .. ' seconds')
        elseif #error_lines > 0 then
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
  if job > 0 and not finished then
    timer = vim.defer_fn(function()
      if finished then return end
      timed_out = true
      vim.fn.jobstop(job)
    end, require('enhance.db.query_timeout').command_seconds * 1000)
  end
end

local sqlserver_queries = {}
local sqlserver_group = vim.api.nvim_create_augroup('EnhanceSQLServerQueries', { clear = true })
vim.api.nvim_create_autocmd({ 'BufWipeout', 'VimLeavePre' }, {
  group = sqlserver_group,
  callback = function(event)
    for key, state in pairs(sqlserver_queries) do
      if event.event == 'VimLeavePre' or key == event.buf then
        sqlserver_queries[key] = nil
        state.runner:cancel()
      end
    end
  end,
})

---Cancel a SQL Server query owned by a query buffer (or the anonymous owner).
---@param query_bufnr number?
---@return boolean
function M.cancel_query(query_bufnr)
  local key = query_bufnr or 0
  local state = sqlserver_queries[key]
  sqlserver_queries[key] = nil
  return state ~= nil and state.runner:cancel() or false
end
M.cancel_sqlserver = M.cancel_query -- Compatibility alias for the shared query owner.

---Execute unchanged server SQL through the structured helper, never CLI text.
---@param connection table SQL Server connection
---@param query string SQL query
---@param query_bufnr number? Optional query buffer number
local function execute_helper(connection, query, query_bufnr)
  if query_bufnr and not vim.api.nvim_buf_is_valid(query_bufnr) then return end
  vim.notify('Executing ' .. connection.type .. ' query...', vim.log.levels.INFO)
  local key = query_bufnr or 0
  local state = sqlserver_queries[key]
  if not state then
    state = { runner = require('enhance.helper_runner').new(), generation = 0 }
    sqlserver_queries[key] = state
  end
  state.generation = state.generation + 1
  local generation = state.generation
  state.runner:run(connection, query, function(response, err)
    if sqlserver_queries[key] ~= state or state.generation ~= generation
      or (query_bufnr and not vim.api.nvim_buf_is_valid(query_bufnr)) then return end
    local metadata = {
      db_type = connection.type, connection_name = connection.name,
      timestamp = os.date('%Y-%m-%d %H:%M:%S'), execution_time = 0, row_count = 0,
      is_error = err ~= nil or not response.ok, transport = 'helper',
    }
    local lines
    if err then
      lines = { 'Query Execution Failed', err }
      -- Also replace parsed metadata in a reused results buffer on transport errors.
      metadata.parsed_result = { headers = {}, rows = {}, metadata = { db_type = connection.type, transport = 'helper' } }
      metadata.result_rows = {}
    else
      metadata.execution_time = response.duration_ms
      metadata.parsed_result = response.parsed_result
      metadata.messages, metadata.errors = response.messages, response.errors
      metadata.affected_rows = response.affected_rows
      local parsed = response.parsed_result
      local sets = parsed.multiple_results and parsed.result_sets or { parsed }
      for _, result in ipairs(sets) do metadata.row_count = metadata.row_count + #result.rows end
      lines, metadata.result_rows = require('enhance.formatter').format(parsed)
      if response.affected_rows ~= vim.NIL then
        lines[#lines + 1] = 'Rows affected: ' .. tostring(response.affected_rows)
      end
      for _, message in ipairs(response.messages) do
        for _, line in ipairs(vim.split(message.message, '\n', { plain = true })) do
          lines[#lines + 1] = 'Message: ' .. line
        end
      end
      for _, error in ipairs(response.errors) do
        local label = 'ERROR: '
        if type(error.number) == 'number' then label = label .. 'Msg ' .. error.number .. ': ' end
        if type(error.sqlState) == 'string' then label = label .. '[' .. error.sqlState .. '] ' end
        for _, line in ipairs(vim.split(error.message, '\n', { plain = true })) do
          lines[#lines + 1] = label .. line
        end
      end
    end
    if metadata.is_error then vim.notify('Query execution failed', vim.log.levels.ERROR) end
    require('enhance.results').display(lines, connection, query_bufnr, metadata)
    local query_upper = query:upper():gsub('^%s+', '')
    if not metadata.is_error and (query_upper:match('^CREATE%s+TABLE')
      or query_upper:match('^DROP%s+TABLE') or query_upper:match('^ALTER%s+TABLE')) then
      local explorer = require('enhance.explorer')
      if explorer.is_open() then explorer.refresh() end
    end
  end)
end

M.execute_sqlserver = execute_helper

-- All network-engine query paths share the same lossless response consumers and ownership.
M.execute_mysql = execute_helper
M.execute_postgres = execute_helper

-- Expose for testing
M._execute_sqlite = M.execute_sqlite
M._execute_sqlserver = M.execute_sqlserver
M._execute_mysql = M.execute_mysql
M._execute_postgres = M.execute_postgres
M._execute_single_sqlite_statement = execute_single_sqlite_statement
M._execute_debatch_sqlite = execute_debatch_sqlite
M._prepare_sqlite_query = sqlite_adapter.prepare_query

return M
