-- Tests for enhance.nvim executor module

describe("enhance.executor", function()
  local executor
  
  before_each(function()
    -- Reset module state before each test
    package.loaded["enhance.executor"] = nil
    executor = require("enhance.executor")
  end)
  
  describe("test_connection", function()
    it("should reject unsupported database type", function()
      local connection = {
        name = "Test DB",
        type = "mongodb",
      }
      
      local success, error_msg = executor.test_connection(connection)
      
      assert.is_false(success)
      assert.is_not_nil(error_msg)
      assert.matches("Unsupported database type", error_msg)
    end)
    
    it("should normalize database type names", function()
      -- Test that different variations are normalized correctly
      local test_cases = {
        { input = "SQL Server", normalized = "sqlserver" },
        { input = "sql-server", normalized = "sqlserver" },
        { input = "sqlserver", normalized = "sqlserver" },
        { input = "MSSQL", normalized = "mssql" },
        { input = "My SQL", normalized = "mysql" },
        { input = "postgres", normalized = "postgres" },
        { input = "PostgreSQL", normalized = "postgresql" },
      }

      for _, test in ipairs(test_cases) do
        local normalized = test.input:lower():gsub("[%s%-_]", "")
        assert.equals(test.normalized, normalized, "Failed for: " .. test.input)
      end
    end)
    
    it("should handle SQLite file not found", function()
      local connection = {
        name = "Test DB",
        type = "sqlite",
        path = "/nonexistent/database.db",
      }
      
      local success, error_msg = executor.test_connection(connection)
      
      assert.is_false(success)
      assert.is_not_nil(error_msg)
      assert.matches("Database file not found", error_msg)
    end)
  end)
  
  describe("execute", function()
    it("should route to correct executor based on database type", function()
      -- Save original executors
      local orig_sqlite = executor._execute_sqlite
      local orig_sqlserver = executor._execute_sqlserver
      local orig_mysql = executor._execute_mysql
      local orig_postgres = executor._execute_postgres

      -- Mock the specific executors
      local sqlite_called = false
      local sqlserver_called = false
      local mysql_called = false
      local postgres_called = false

      executor._execute_sqlite = function() sqlite_called = true end
      executor._execute_sqlserver = function() sqlserver_called = true end
      executor._execute_mysql = function() mysql_called = true end
      executor._execute_postgres = function() postgres_called = true end

      -- Also update the module functions
      executor.execute_sqlite = executor._execute_sqlite
      executor.execute_sqlserver = executor._execute_sqlserver
      executor.execute_mysql = executor._execute_mysql
      executor.execute_postgres = executor._execute_postgres

      -- Test SQLite routing
      executor.execute({ type = "sqlite", path = "/tmp/test.db" }, "SELECT 1")
      assert.is_true(sqlite_called)

      -- Test SQL Server routing
      executor.execute({ type = "sqlserver" }, "SELECT 1")
      assert.is_true(sqlserver_called)

      -- Test MySQL routing
      executor.execute({ type = "mysql" }, "SELECT 1")
      assert.is_true(mysql_called)

      -- Test PostgreSQL routing
      executor.execute({ type = "postgres" }, "SELECT 1")
      assert.is_true(postgres_called)

      -- Restore
      executor._execute_sqlite = orig_sqlite
      executor._execute_sqlserver = orig_sqlserver
      executor._execute_mysql = orig_mysql
      executor._execute_postgres = orig_postgres
      executor.execute_sqlite = orig_sqlite
      executor.execute_sqlserver = orig_sqlserver
      executor.execute_mysql = orig_mysql
      executor.execute_postgres = orig_postgres
    end)
    
    it("should normalize database type before routing", function()
      -- Save original
      local orig_sqlserver = executor._execute_sqlserver

      local called = false
      executor._execute_sqlserver = function() called = true end
      executor.execute_sqlserver = executor._execute_sqlserver

      -- Test with different SQL Server variations
      executor.execute({ type = "SQL Server" }, "SELECT 1")
      assert.is_true(called)

      called = false
      executor.execute({ type = "sql-server" }, "SELECT 1")
      assert.is_true(called)

      called = false
      executor.execute({ type = "MSSQL" }, "SELECT 1")
      assert.is_true(called)

      -- Restore
      executor._execute_sqlserver = orig_sqlserver
      executor.execute_sqlserver = orig_sqlserver
    end)
    
    it("should handle unsupported database type", function()
      -- Mock vim.notify to capture error
      local notified = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        notified = true
        assert.matches("not yet supported", msg)
        assert.equals(vim.log.levels.ERROR, level)
      end
      
      executor.execute({ type = "mongodb" }, "SELECT 1")
      
      -- Restore
      vim.notify = original_notify
      
      assert.is_true(notified)
    end)
  end)
  
  describe("execute_sqlite", function()
    it("should notify when database file not found", function()
      local connection = {
        name = "Test DB",
        type = "sqlite",
        path = "/nonexistent/database.db",
      }
      
      -- Mock vim.notify
      local notified = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match("Database file not found") then
          notified = true
          assert.equals(vim.log.levels.ERROR, level)
        end
      end
      
      executor._execute_sqlite(connection, "SELECT 1")
      
      -- Restore
      vim.notify = original_notify
      
      assert.is_true(notified)
    end)
  end)

  describe("query type detection", function()
    it("should detect CREATE TABLE query", function()
      local query = "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)"
      local query_upper = query:upper()

      local query_type = nil
      if query_upper:match("^CREATE%s+TABLE") then
        query_type = "CREATE_TABLE"
      end

      assert.equals("CREATE_TABLE", query_type)
    end)

    it("should detect DROP TABLE query", function()
      local query = "DROP TABLE users"
      local query_upper = query:upper()

      local query_type = nil
      if query_upper:match("^DROP%s+TABLE") then
        query_type = "DROP_TABLE"
      end

      assert.equals("DROP_TABLE", query_type)
    end)

    it("should detect ALTER TABLE query", function()
      local query = "ALTER TABLE users ADD COLUMN email TEXT"
      local query_upper = query:upper()

      local query_type = nil
      if query_upper:match("^ALTER%s+TABLE") then
        query_type = "ALTER_TABLE"
      end

      assert.equals("ALTER_TABLE", query_type)
    end)

    it("should detect INSERT query", function()
      local query = "INSERT INTO users (name) VALUES ('Alice')"
      local query_upper = query:upper()

      local query_type = nil
      if query_upper:match("^INSERT%s") then
        query_type = "INSERT"
      end

      assert.equals("INSERT", query_type)
    end)

    it("should detect UPDATE query", function()
      local query = "UPDATE users SET name = 'Bob' WHERE id = 1"
      local query_upper = query:upper()

      local query_type = nil
      if query_upper:match("^UPDATE%s") then
        query_type = "UPDATE"
      end

      assert.equals("UPDATE", query_type)
    end)

    it("should detect DELETE query", function()
      local query = "DELETE FROM users WHERE id = 1"
      local query_upper = query:upper()

      local query_type = nil
      if query_upper:match("^DELETE%s") then
        query_type = "DELETE"
      end

      assert.equals("DELETE", query_type)
    end)

    it("should not detect query type for SELECT", function()
      local query = "SELECT * FROM users"
      local query_upper = query:upper()

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

      assert.is_nil(query_type, "SELECT should not have a query_type")
    end)
  end)

  describe("execute_sqlserver error handling", function()
    it("should capture and display SQL Server errors in results window", function()
      -- Mock connection
      local connection = {
        name = "Test SQL Server",
        type = "sqlserver",
        server = "localhost",
        database = "testdb",
      }

      -- Mock vim.fn.jobstart to simulate error
      local original_jobstart = vim.fn.jobstart
      local stderr_callback
      local exit_callback

      vim.fn.jobstart = function(cmd, opts)
        stderr_callback = opts.on_stderr
        exit_callback = opts.on_exit
        return 1 -- job id
      end

      -- Mock results.display_message
      local display_message_called = false
      local displayed_lines
      local original_results = package.loaded["enhance.results"]
      package.loaded["enhance.results"] = {
        display_message = function(lines)
          display_message_called = true
          displayed_lines = lines
        end
      }

      -- Mock vim.notify to suppress output
      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match("Query execution failed") then
          notify_called = true
        end
      end

      -- Execute query
      executor._execute_sqlserver(connection, "SELECT * FROM nonexistent")

      -- Simulate stderr output (SQL Server error message)
      stderr_callback(nil, {"Msg 208, Level 16, State 1", "Invalid object name 'nonexistent'."})

      -- Simulate error exit
      exit_callback(nil, 1)

      -- Verify error was captured and displayed
      assert.is_true(display_message_called, "display_message should be called")
      assert.is_not_nil(displayed_lines, "displayed_lines should not be nil")
      assert.equals("Query Execution Failed", displayed_lines[1])
      assert.matches("Msg 208", displayed_lines[2])
      assert.matches("Invalid object name", displayed_lines[3])

      -- Verify notification was shown
      assert.is_true(notify_called, "vim.notify should be called for errors")

      -- Restore
      vim.fn.jobstart = original_jobstart
      package.loaded["enhance.results"] = original_results
      vim.notify = original_notify
    end)

    it("should handle empty stderr with exit code", function()
      -- Mock connection
      local connection = {
        name = "Test SQL Server",
        type = "sqlserver",
        server = "localhost",
        database = "testdb",
      }

      -- Mock vim.fn.jobstart
      local original_jobstart = vim.fn.jobstart
      local exit_callback

      vim.fn.jobstart = function(cmd, opts)
        exit_callback = opts.on_exit
        return 1
      end

      -- Mock results.display_message
      local displayed_lines
      local original_results = package.loaded["enhance.results"]
      package.loaded["enhance.results"] = {
        display_message = function(lines)
          displayed_lines = lines
        end
      }

      -- Mock vim.notify
      local original_notify = vim.notify
      vim.notify = function() end

      -- Execute query
      executor._execute_sqlserver(connection, "SELECT 1")

      -- Simulate error exit with no stderr
      exit_callback(nil, 1)

      -- Verify error display includes exit code
      assert.is_not_nil(displayed_lines)
      assert.equals("Query Execution Failed", displayed_lines[1])
      assert.matches("Exit code: 1", displayed_lines[2])

      -- Restore
      vim.fn.jobstart = original_jobstart
      package.loaded["enhance.results"] = original_results
      vim.notify = original_notify
    end)

    it("should detect SQL errors in output even with exit code 0", function()
      -- Mock connection
      local connection = {
        name = "Test SQL Server",
        type = "sqlserver",
        server = "localhost",
        database = "testdb",
      }

      -- Mock vim.fn.jobstart
      local original_jobstart = vim.fn.jobstart
      local stdout_callback
      local exit_callback

      vim.fn.jobstart = function(cmd, opts)
        stdout_callback = opts.on_stdout
        exit_callback = opts.on_exit
        return 1
      end

      -- Mock results.display_message
      local display_message_called = false
      local displayed_lines
      local original_results = package.loaded["enhance.results"]
      package.loaded["enhance.results"] = {
        display_message = function(lines)
          display_message_called = true
          displayed_lines = lines
        end
      }

      -- Mock vim.notify
      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match("Query execution failed") then
          notify_called = true
        end
      end

      -- Execute query
      executor._execute_sqlserver(connection, "SELECT * FROM nonexistent")

      -- Simulate SQL error in stdout (exit code 0!)
      stdout_callback(nil, {
        "Msg 208, Level 16, State 1, Server testserver, Line 1",
        "Invalid object name 'nonexistent'."
      })

      -- Simulate SUCCESS exit code (sqlcmd returns 0 for SQL errors)
      exit_callback(nil, 0)

      -- Verify SQL error was detected and displayed
      assert.is_true(display_message_called, "display_message should be called for SQL errors")
      assert.is_not_nil(displayed_lines)
      assert.equals("Query Execution Failed", displayed_lines[1])
      assert.matches("Msg 208", displayed_lines[3])
      assert.matches("Invalid object name", displayed_lines[4])

      -- Verify notification was shown
      assert.is_true(notify_called, "vim.notify should be called for SQL errors")

      -- Restore
      vim.fn.jobstart = original_jobstart
      package.loaded["enhance.results"] = original_results
      vim.notify = original_notify
    end)

    it("should detect syntax errors (Msg 102)", function()
      -- Mock connection
      local connection = {
        name = "Test SQL Server",
        type = "sqlserver",
        server = "localhost",
        database = "testdb",
      }

      -- Mock vim.fn.jobstart
      local original_jobstart = vim.fn.jobstart
      local stdout_callback
      local exit_callback

      vim.fn.jobstart = function(cmd, opts)
        stdout_callback = opts.on_stdout
        exit_callback = opts.on_exit
        return 1
      end

      -- Mock results.display_message
      local display_message_called = false
      local displayed_lines
      local original_results = package.loaded["enhance.results"]
      package.loaded["enhance.results"] = {
        display_message = function(lines)
          display_message_called = true
          displayed_lines = lines
        end
      }

      -- Mock vim.notify
      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match("Query execution failed") then
          notify_called = true
        end
      end

      -- Execute query with syntax error
      executor._execute_sqlserver(connection, "SELECT * FORM TestTable")

      -- Simulate syntax error in stdout (exit code 0)
      stdout_callback(nil, {
        "Msg 102, Level 15, State 1, Server testserver, Line 1",
        "Incorrect syntax near 'FORM'."
      })

      -- Simulate SUCCESS exit code (sqlcmd returns 0 for SQL errors)
      exit_callback(nil, 0)

      -- Verify SQL error was detected and displayed
      assert.is_true(display_message_called, "display_message should be called for syntax errors")
      assert.is_not_nil(displayed_lines)
      assert.equals("Query Execution Failed", displayed_lines[1])
      assert.matches("Msg 102", displayed_lines[3])
      assert.matches("Incorrect syntax", displayed_lines[4])

      -- Verify notification was shown
      assert.is_true(notify_called, "vim.notify should be called for syntax errors")

      -- Restore
      vim.fn.jobstart = original_jobstart
      package.loaded["enhance.results"] = original_results
      vim.notify = original_notify
    end)

    it("should detect constraint violations (Msg 2627)", function()
      -- Mock connection
      local connection = {
        name = "Test SQL Server",
        type = "sqlserver",
        server = "localhost",
        database = "testdb",
      }

      -- Mock execute_single_sqlserver_statement helper (can't mock vim.v.shell_error - it's read-only)
      local original_helper = executor._execute_single_sqlserver_statement
      executor._execute_single_sqlserver_statement = function(conn, stmt_text)
        -- Return error for constraint violation
        local error_msg = table.concat({
          "Msg 2627, Level 14, State 1, Server testserver, Line 2",
          "Violation of PRIMARY KEY constraint 'PK_TestTable'. Cannot insert duplicate key in object 'dbo.TestTable'. The duplicate key value is (1).",
          "The statement has been terminated."
        }, "\n")
        return nil, error_msg, 45.2, 0
      end

      -- Mock results.display (debatch mode uses display, not display_message)
      local display_called = false
      local displayed_lines
      local displayed_metadata
      local original_results = package.loaded["enhance.results"]
      package.loaded["enhance.results"] = {
        display = function(lines, conn, bufnr, metadata)
          display_called = true
          displayed_lines = lines
          displayed_metadata = metadata
        end
      }

      -- Mock vim.notify
      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match("Query execution failed") then
          notify_called = true
        end
      end

      -- Execute query with constraint violation
      executor._execute_sqlserver(connection, "INSERT INTO TestTable VALUES (1, 'Duplicate')")

      -- Verify SQL error was detected and displayed
      assert.is_true(display_called, "display should be called for constraint violations")
      assert.is_not_nil(displayed_lines)
      assert.is_not_nil(displayed_metadata)
      assert.is_true(displayed_metadata.is_error, "metadata should indicate error")
      -- Verify error details are included in output
      assert.matches("Query Execution Failed", table.concat(displayed_lines, "\n"))
      assert.matches("Msg 2627", table.concat(displayed_lines, "\n"))
      assert.matches("PRIMARY KEY constraint", table.concat(displayed_lines, "\n"))

      -- Verify notification was shown
      assert.is_true(notify_called, "vim.notify should be called for constraint violations")

      -- Restore
      executor._execute_single_sqlserver_statement = original_helper
      package.loaded["enhance.results"] = original_results
      vim.notify = original_notify
    end)

    it("should detect DDL errors (Msg 2714)", function()
      -- Mock connection
      local connection = {
        name = "Test SQL Server",
        type = "sqlserver",
        server = "localhost",
        database = "testdb",
      }

      -- Mock execute_single_sqlserver_statement helper (can't mock vim.v.shell_error - it's read-only)
      local original_helper = executor._execute_single_sqlserver_statement
      executor._execute_single_sqlserver_statement = function(conn, stmt_text)
        -- Return error for DDL error
        local error_msg = table.concat({
          "Msg 2714, Level 16, State 6, Server testserver, Line 1",
          "There is already an object named 'TestTable' in the database."
        }, "\n")
        return nil, error_msg, 32.1, 0
      end

      -- Mock results.display (debatch mode uses display, not display_message)
      local display_called = false
      local displayed_lines
      local displayed_metadata
      local original_results = package.loaded["enhance.results"]
      package.loaded["enhance.results"] = {
        display = function(lines, conn, bufnr, metadata)
          display_called = true
          displayed_lines = lines
          displayed_metadata = metadata
        end
      }

      -- Mock vim.notify
      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match("Query execution failed") then
          notify_called = true
        end
      end

      -- Execute query with DDL error
      executor._execute_sqlserver(connection, "CREATE TABLE TestTable (ID INT)")

      -- Verify SQL error was detected and displayed
      assert.is_true(display_called, "display should be called for DDL errors")
      assert.is_not_nil(displayed_lines)
      assert.is_not_nil(displayed_metadata)
      assert.is_true(displayed_metadata.is_error, "metadata should indicate error")
      -- Verify error details are included in output
      assert.matches("Query Execution Failed", table.concat(displayed_lines, "\n"))
      assert.matches("Msg 2714", table.concat(displayed_lines, "\n"))
      assert.matches("already an object", table.concat(displayed_lines, "\n"))

      -- Verify notification was shown
      assert.is_true(notify_called, "vim.notify should be called for DDL errors")

      -- Restore
      executor._execute_single_sqlserver_statement = original_helper
      package.loaded["enhance.results"] = original_results
      vim.notify = original_notify
    end)

    it("should detect errors in multiple statements with partial success", function()
      -- Mock connection
      local connection = {
        name = "Test SQL Server",
        type = "sqlserver",
        server = "localhost",
        database = "testdb",
      }

      -- Mock vim.fn.jobstart
      local original_jobstart = vim.fn.jobstart
      local stdout_callback
      local exit_callback

      vim.fn.jobstart = function(cmd, opts)
        stdout_callback = opts.on_stdout
        exit_callback = opts.on_exit
        return 1
      end

      -- Mock results.display_message
      local display_message_called = false
      local displayed_lines
      local original_results = package.loaded["enhance.results"]
      package.loaded["enhance.results"] = {
        display_message = function(lines)
          display_message_called = true
          displayed_lines = lines
        end
      }

      -- Mock vim.notify
      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match("Query execution failed") then
          notify_called = true
        end
      end

      -- Execute multiple statements (first succeeds, second fails)
      executor._execute_sqlserver(connection, "SELECT * FROM TestTable; SELECT * FROM NonExistent;")

      -- Simulate partial success in stdout (first SELECT succeeds, second fails)
      stdout_callback(nil, {
        "Name|Email",
        "----|-----",
        "Test1|test1@example.com",
        "(1 row affected)",
        "Msg 208, Level 16, State 1, Server testserver, Line 2",
        "Invalid object name 'NonExistent'."
      })

      -- Simulate SUCCESS exit code (sqlcmd returns 0 for SQL errors)
      exit_callback(nil, 0)

      -- Verify SQL error was detected and displayed
      assert.is_true(display_message_called, "display_message should be called for errors with partial success")
      assert.is_not_nil(displayed_lines)
      assert.equals("Query Execution Failed", displayed_lines[1])
      -- Verify partial success data is included in output
      assert.matches("Name|Email", table.concat(displayed_lines, "\n"))
      assert.matches("Test1", table.concat(displayed_lines, "\n"))
      -- Verify error is included
      assert.matches("Msg 208", table.concat(displayed_lines, "\n"))
      assert.matches("Invalid object name", table.concat(displayed_lines, "\n"))

      -- Verify notification was shown
      assert.is_true(notify_called, "vim.notify should be called for errors")

      -- Restore
      vim.fn.jobstart = original_jobstart
      package.loaded["enhance.results"] = original_results
      vim.notify = original_notify
    end)

    it("should detect errors in mixed statements (INSERT + SELECT)", function()
      -- Mock connection
      local connection = {
        name = "Test SQL Server",
        type = "sqlserver",
        server = "localhost",
        database = "testdb",
      }

      -- Mock execute_single_sqlserver_statement helper (can't mock vim.v.shell_error - it's read-only)
      -- Will be called twice: once for INSERT (success), once for SELECT (error)
      local original_helper = executor._execute_single_sqlserver_statement
      local call_count = 0
      executor._execute_single_sqlserver_statement = function(conn, stmt_text)
        call_count = call_count + 1
        if call_count == 1 then
          -- First call: INSERT succeeds
          local parsed_result = { headers = {}, rows = {} }
          return parsed_result, nil, 28.5, 1
        else
          -- Second call: SELECT fails
          local error_msg = table.concat({
            "Msg 208, Level 16, State 1, Server testserver, Line 2",
            "Invalid object name 'NonExistent'."
          }, "\n")
          return nil, error_msg, 15.3, 0
        end
      end

      -- Mock results.display (debatch mode uses display, not display_message)
      local display_called = false
      local displayed_lines
      local displayed_metadata
      local original_results = package.loaded["enhance.results"]
      package.loaded["enhance.results"] = {
        display = function(lines, conn, bufnr, metadata)
          display_called = true
          displayed_lines = lines
          displayed_metadata = metadata
        end
      }

      -- Mock vim.notify
      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match("Query execution failed") then
          notify_called = true
        end
      end

      -- Execute mixed statements (INSERT succeeds, SELECT fails)
      executor._execute_sqlserver(connection, "INSERT INTO TestTable VALUES ('Test'); SELECT * FROM NonExistent;")

      -- Verify SQL error was detected and displayed
      assert.is_true(display_called, "display should be called for errors in mixed statements")
      assert.is_not_nil(displayed_lines)
      assert.is_not_nil(displayed_metadata)
      assert.is_true(displayed_metadata.is_error, "metadata should indicate error")
      -- Verify error details are included in output
      assert.matches("Query Execution Failed", table.concat(displayed_lines, "\n"))
      assert.matches("Msg 208", table.concat(displayed_lines, "\n"))
      assert.matches("Invalid object name", table.concat(displayed_lines, "\n"))

      -- Verify notification was shown
      assert.is_true(notify_called, "vim.notify should be called for errors")

      -- Restore
      executor._execute_single_sqlserver_statement = original_helper
      package.loaded["enhance.results"] = original_results
      vim.notify = original_notify
    end)
  end)

  -- Note: execute_single_sqlserver_statement tests require a real SQL Server instance
  -- The function uses vim.v.shell_error which is read-only in test environment
  -- Manual testing will be performed during debatching implementation
  -- Integration tests will be added once debatching is complete
end)

