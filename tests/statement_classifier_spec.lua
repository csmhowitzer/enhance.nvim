-- Tests for statement_classifier.lua
local classifier = require("enhance.statement_classifier")

describe("statement_classifier", function()
  describe("classify_for_execution", function()
    it("should return batch mode for empty statements", function()
      local result = classifier.classify_for_execution({})
      assert.equals("batch", result.execution_mode)
      assert.equals("no_statements", result.reason)
    end)

    it("should detect transaction block and return batch mode", function()
      local statements = {
        { type = "UNKNOWN", text = "BEGIN TRANSACTION" },
        { type = "UPDATE", text = "UPDATE users SET status='active' WHERE id=1" },
        { type = "UPDATE", text = "UPDATE users SET status='inactive' WHERE id=2" },
        { type = "UNKNOWN", text = "COMMIT" },
      }
      
      local result = classifier.classify_for_execution(statements)
      assert.equals("batch", result.execution_mode)
      assert.equals("transaction_block", result.reason)
      assert.equals(1, #result.groups)
      assert.equals("batch", result.groups[1].type)
      assert.equals(4, #result.groups[1].statements)
    end)

    it("should return batch mode for metadata queries only", function()
      local statements = {
        { type = "PRAGMA", text = "PRAGMA table_info(users)" },
        { type = "PRAGMA", text = "PRAGMA foreign_keys" },
      }
      
      local result = classifier.classify_for_execution(statements)
      assert.equals("batch", result.execution_mode)
      assert.equals("metadata_queries", result.reason)
    end)

    it("should return debatch mode for DML statements", function()
      local statements = {
        { type = "UPDATE", text = "UPDATE users SET status='active' WHERE id=1" },
        { type = "UPDATE", text = "UPDATE users SET status='inactive' WHERE id=2" },
      }
      
      local result = classifier.classify_for_execution(statements)
      assert.equals("debatch", result.execution_mode)
      assert.equals("individual_statements", result.reason)
      assert.equals(2, #result.groups)
      assert.equals("individual", result.groups[1].type)
      assert.equals("individual", result.groups[2].type)
    end)

    it("should return debatch mode for DDL statements", function()
      local statements = {
        { type = "CREATE", text = "CREATE TABLE test (id INT)" },
        { type = "DROP", text = "DROP TABLE test" },
      }
      
      local result = classifier.classify_for_execution(statements)
      assert.equals("debatch", result.execution_mode)
      assert.equals(2, #result.groups)
    end)

    it("should group consecutive batch statements in debatch mode", function()
      local statements = {
        { type = "INSERT", text = "INSERT INTO users VALUES (1, 'Alice')" },
        { type = "SELECT", text = "SELECT * FROM users WHERE id=1" },
        { type = "PRAGMA", text = "PRAGMA table_info(users)" },
        { type = "DELETE", text = "DELETE FROM users WHERE id=1" },
      }
      
      local result = classifier.classify_for_execution(statements)
      assert.equals("debatch", result.execution_mode)
      assert.equals(3, #result.groups)
      
      -- Group 1: INSERT (individual)
      assert.equals("individual", result.groups[1].type)
      assert.equals(1, #result.groups[1].statements)
      
      -- Group 2: SELECT + PRAGMA (batched together)
      assert.equals("batch", result.groups[2].type)
      assert.equals(2, #result.groups[2].statements)
      
      -- Group 3: DELETE (individual)
      assert.equals("individual", result.groups[3].type)
      assert.equals(1, #result.groups[3].statements)
    end)

    it("should handle mixed DML and SELECT statements", function()
      local statements = {
        { type = "INSERT", text = "INSERT INTO users VALUES (99, 'Test')" },
        { type = "SELECT", text = "SELECT * FROM users WHERE id=99" },
        { type = "DELETE", text = "DELETE FROM users WHERE id=99" },
      }
      
      local result = classifier.classify_for_execution(statements)
      assert.equals("debatch", result.execution_mode)
      assert.equals(3, #result.groups)
      assert.equals("individual", result.groups[1].type)  -- INSERT
      assert.equals("batch", result.groups[2].type)       -- SELECT
      assert.equals("individual", result.groups[3].type)  -- DELETE
    end)
  end)

  describe("_should_debatch", function()
    it("should return true for DML statements", function()
      assert.is_true(classifier._should_debatch("INSERT"))
      assert.is_true(classifier._should_debatch("UPDATE"))
      assert.is_true(classifier._should_debatch("DELETE"))
    end)

    it("should return true for DDL statements", function()
      assert.is_true(classifier._should_debatch("CREATE"))
      assert.is_true(classifier._should_debatch("DROP"))
      assert.is_true(classifier._should_debatch("ALTER"))
      assert.is_true(classifier._should_debatch("TRUNCATE"))
    end)

    it("should return false for SELECT", function()
      assert.is_false(classifier._should_debatch("SELECT"))
    end)

    it("should return false for metadata queries", function()
      assert.is_false(classifier._should_debatch("PRAGMA"))
      assert.is_false(classifier._should_debatch("SHOW"))
      assert.is_false(classifier._should_debatch("EXPLAIN"))
    end)
  end)

  describe("_should_batch", function()
    it("should return true for SELECT", function()
      assert.is_true(classifier._should_batch("SELECT"))
    end)

    it("should return true for metadata queries", function()
      assert.is_true(classifier._should_batch("PRAGMA"))
      assert.is_true(classifier._should_batch("SHOW"))
      assert.is_true(classifier._should_batch("EXPLAIN"))
      assert.is_true(classifier._should_batch("DESCRIBE"))
    end)

    it("should return false for DML/DDL", function()
      assert.is_false(classifier._should_batch("INSERT"))
      assert.is_false(classifier._should_batch("UPDATE"))
      assert.is_false(classifier._should_batch("CREATE"))
    end)
  end)
end)

