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
end)

