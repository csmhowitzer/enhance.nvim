-- Tests for de-batch execution
-- Tests the new de-batching functionality for DML/DDL statements

describe("enhance.executor de-batch execution", function()
  local executor
  local test_db_path
  
  before_each(function()
    executor = require("enhance.executor")
    
    -- Create a temporary test database
    test_db_path = vim.fn.tempname() .. ".db"
    
    -- Initialize database with test table
    local init_sql = [[
      CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, status TEXT);
      INSERT INTO users VALUES (1, 'Alice', 'active');
      INSERT INTO users VALUES (2, 'Bob', 'inactive');
      INSERT INTO users VALUES (3, 'Charlie', 'active');
    ]]
    
    vim.fn.system(string.format("sqlite3 %s %s",
      vim.fn.shellescape(test_db_path),
      vim.fn.shellescape(init_sql)))
  end)
  
  after_each(function()
    -- Clean up test database
    if test_db_path and vim.fn.filereadable(test_db_path) == 1 then
      vim.fn.delete(test_db_path)
    end
  end)
  
  describe("classification routing", function()
    it("should use batch mode for transaction blocks", function()
      local connection = {
        name = "Test DB",
        type = "sqlite",
        path = test_db_path,
      }
      
      local query = [[
        BEGIN TRANSACTION;
        UPDATE users SET status='active' WHERE id=1;
        UPDATE users SET status='inactive' WHERE id=2;
        COMMIT;
      ]]
      
      -- This should use batch mode (not de-batch)
      local statement_detector = require("enhance.statement_detector")
      local statements = statement_detector.detect_statements(query)
      
      local statement_classifier = require("enhance.statement_classifier")
      local classification = statement_classifier.classify_for_execution(statements)
      
      assert.equals("batch", classification.execution_mode)
      assert.equals("transaction_block", classification.reason)
    end)
    
    it("should use debatch mode for multiple DML statements", function()
      local query = [[
        UPDATE users SET status='active' WHERE id=1;
        UPDATE users SET status='inactive' WHERE id=2;
      ]]
      
      local statement_detector = require("enhance.statement_detector")
      local statements = statement_detector.detect_statements(query)
      
      local statement_classifier = require("enhance.statement_classifier")
      local classification = statement_classifier.classify_for_execution(statements)
      
      assert.equals("debatch", classification.execution_mode)
      assert.equals("individual_statements", classification.reason)
      assert.equals(2, #classification.groups)
    end)
    
    it("should use batch mode for metadata queries", function()
      local query = [[
        PRAGMA table_info(users);
        PRAGMA foreign_keys;
      ]]
      
      local statement_detector = require("enhance.statement_detector")
      local statements = statement_detector.detect_statements(query)
      
      local statement_classifier = require("enhance.statement_classifier")
      local classification = statement_classifier.classify_for_execution(statements)
      
      assert.equals("batch", classification.execution_mode)
      assert.equals("metadata_queries", classification.reason)
    end)
  end)
  
  describe("single statement execution", function()
    it("should execute single UPDATE statement", function()
      local connection = {
        name = "Test DB",
        type = "sqlite",
        path = test_db_path,
      }
      
      local query = "UPDATE users SET status='active' WHERE id=2"
      
      -- Execute using the internal function
      local execute_single = executor._execute_single_sqlite_statement
      if execute_single then
        local parsed, err, duration, row_count = execute_single(connection, query)
        
        assert.is_nil(err)
        assert.is_not_nil(parsed)
        assert.equals(1, row_count)
        assert.is_true(duration > 0)
      end
    end)
    
    it("should execute single SELECT statement", function()
      local connection = {
        name = "Test DB",
        type = "sqlite",
        path = test_db_path,
      }
      
      local query = "SELECT * FROM users WHERE status='active'"
      
      local execute_single = executor._execute_single_sqlite_statement
      if execute_single then
        local parsed, err, duration, row_count = execute_single(connection, query)
        
        assert.is_nil(err)
        assert.is_not_nil(parsed)
        assert.is_true(row_count >= 2) -- Alice and Charlie
        assert.is_not_nil(parsed.headers)
        assert.is_not_nil(parsed.rows)
      end
    end)
    
    it("should handle SQL errors gracefully", function()
      local connection = {
        name = "Test DB",
        type = "sqlite",
        path = test_db_path,
      }
      
      local query = "UPDATE nonexistent_table SET col='value'"
      
      local execute_single = executor._execute_single_sqlite_statement
      if execute_single then
        local parsed, err, duration, row_count = execute_single(connection, query)
        
        assert.is_nil(parsed)
        assert.is_not_nil(err)
        assert.is_true(err:match("no such table") ~= nil)
      end
    end)
  end)
end)

