-- Tests for SQL statement matcher
-- Matches detected statements to parsed output

describe("statement_matcher", function()
  local matcher

  before_each(function()
    matcher = require("enhance.statement_matcher")
  end)

  describe("match_statements", function()
    describe("single SELECT statement", function()
      it("should match SELECT to result table", function()
        local statements = {
          { type = "SELECT", text = "SELECT * FROM Users" }
        }
        
        local parsed_output = {
          headers = { "id", "name" },
          rows = { { "1", "Alice" }, { "2", "Bob" } },
          metadata = { db_type = "sqlite" }
        }
        
        local metadata = {
          execution_time = 12.5,
          row_count = 2,
          db_type = "sqlite",
          timestamp = "2025-01-26 20:00:00",
          connection_name = "test.db"
        }
        
        local results = matcher.match_statements(statements, parsed_output, metadata)
        
        assert.equals(1, #results)
        assert.equals("SELECT", results[1].type)
        assert.equals("SELECT * FROM Users", results[1].query_text)
        assert.is_not_nil(results[1].result_table)
        assert.are.same({ "id", "name" }, results[1].result_table.headers)
        assert.equals(2, #results[1].result_table.rows)
        assert.equals(2, results[1].rows)
        assert.equals(12.5, results[1].elapsed)
        assert.equals("sqlite", results[1].db_type)
        assert.equals("test.db", results[1].db_name)
      end)
    end)

    describe("INSERT statement", function()
      it("should match INSERT to row count with no result table", function()
        local statements = {
          { type = "INSERT", text = "INSERT INTO Users VALUES (1, 'Alice')" }
        }
        
        local parsed_output = {
          headers = {},
          rows = {},
          metadata = { db_type = "sqlite" }
        }
        
        local metadata = {
          execution_time = 5.2,
          row_count = 1,
          db_type = "sqlite",
          timestamp = "2025-01-26 20:00:00",
          connection_name = "test.db",
          query_type = "INSERT"
        }
        
        local results = matcher.match_statements(statements, parsed_output, metadata)
        
        assert.equals(1, #results)
        assert.equals("INSERT", results[1].type)
        assert.is_nil(results[1].result_table)
        assert.equals(1, results[1].rows)
        assert.equals("✓ 1 row inserted", results[1].message)
      end)

      it("should handle multiple rows inserted", function()
        local statements = {
          { type = "INSERT", text = "INSERT INTO Users VALUES (1, 'Alice'), (2, 'Bob')" }
        }
        
        local parsed_output = {
          headers = {},
          rows = {},
          metadata = { db_type = "sqlite" }
        }
        
        local metadata = {
          execution_time = 8.3,
          row_count = 2,
          db_type = "sqlite",
          query_type = "INSERT"
        }
        
        local results = matcher.match_statements(statements, parsed_output, metadata)
        
        assert.equals(1, #results)
        assert.equals("✓ 2 rows inserted", results[1].message)
      end)
    end)

    describe("UPDATE statement", function()
      it("should match UPDATE to row count", function()
        local statements = {
          { type = "UPDATE", text = "UPDATE Users SET name = 'Bob' WHERE id = 1" }
        }
        
        local parsed_output = {
          headers = {},
          rows = {},
          metadata = { db_type = "sqlite" }
        }
        
        local metadata = {
          execution_time = 6.1,
          row_count = 1,
          db_type = "sqlite",
          query_type = "UPDATE"
        }
        
        local results = matcher.match_statements(statements, parsed_output, metadata)
        
        assert.equals(1, #results)
        assert.equals("UPDATE", results[1].type)
        assert.equals("✓ 1 row updated", results[1].message)
      end)
    end)

    describe("DELETE statement", function()
      it("should match DELETE to row count", function()
        local statements = {
          { type = "DELETE", text = "DELETE FROM Users WHERE id = 1" }
        }

        local parsed_output = {
          headers = {},
          rows = {},
          metadata = { db_type = "sqlite" }
        }

        local metadata = {
          execution_time = 4.8,
          row_count = 1,
          db_type = "sqlite",
          query_type = "DELETE"
        }

        local results = matcher.match_statements(statements, parsed_output, metadata)

        assert.equals(1, #results)
        assert.equals("DELETE", results[1].type)
        assert.equals("✓ 1 row deleted", results[1].message)
      end)
    end)

    describe("DDL statements", function()
      it("should match CREATE TABLE with success message", function()
        local statements = {
          { type = "CREATE", text = "CREATE TABLE Users (id INT, name TEXT)" }
        }

        local parsed_output = {
          headers = {},
          rows = {},
          metadata = { db_type = "sqlite" }
        }

        local metadata = {
          execution_time = 3.2,
          row_count = 0,
          db_type = "sqlite",
          query_type = "CREATE_TABLE"
        }

        local results = matcher.match_statements(statements, parsed_output, metadata)

        assert.equals(1, #results)
        assert.equals("CREATE", results[1].type)
        assert.is_nil(results[1].result_table)
        assert.equals("✓ Table created successfully", results[1].message)
      end)

      it("should match DROP TABLE with success message", function()
        local statements = {
          { type = "DROP", text = "DROP TABLE Users" }
        }

        local parsed_output = {
          headers = {},
          rows = {},
          metadata = { db_type = "sqlite" }
        }

        local metadata = {
          execution_time = 2.1,
          row_count = 0,
          db_type = "sqlite",
          query_type = "DROP_TABLE"
        }

        local results = matcher.match_statements(statements, parsed_output, metadata)

        assert.equals(1, #results)
        assert.equals("DROP", results[1].type)
        assert.equals("✓ Table dropped successfully", results[1].message)
      end)

      it("should match ALTER TABLE with success message", function()
        local statements = {
          { type = "ALTER", text = "ALTER TABLE Users ADD COLUMN age INT" }
        }

        local parsed_output = {
          headers = {},
          rows = {},
          metadata = { db_type = "sqlite" }
        }

        local metadata = {
          execution_time = 4.5,
          row_count = 0,
          db_type = "sqlite",
          query_type = "ALTER_TABLE"
        }

        local results = matcher.match_statements(statements, parsed_output, metadata)

        assert.equals(1, #results)
        assert.equals("ALTER", results[1].type)
        assert.equals("✓ Table altered successfully", results[1].message)
      end)
    end)

    describe("mixed statements", function()
      it("should match INSERT followed by SELECT", function()
        local statements = {
          { type = "INSERT", text = "INSERT INTO Users VALUES (1, 'Alice')" },
          { type = "SELECT", text = "SELECT * FROM Users" }
        }

        local parsed_output = {
          multiple_results = true,
          result_sets = {
            { headers = {}, rows = {}, metadata = { db_type = "sqlite" } },
            { headers = { "id", "name" }, rows = { { "1", "Alice" } }, metadata = { db_type = "sqlite" } }
          },
          metadata = { db_type = "sqlite" }
        }

        local metadata = {
          execution_time = 15.3,
          row_count = 1,
          db_type = "sqlite"
        }

        local results = matcher.match_statements(statements, parsed_output, metadata)

        assert.equals(2, #results)

        -- First result: INSERT
        assert.equals("INSERT", results[1].type)
        assert.is_nil(results[1].result_table)
        assert.equals("✓ 1 row inserted", results[1].message)

        -- Second result: SELECT
        assert.equals("SELECT", results[2].type)
        assert.is_not_nil(results[2].result_table)
        assert.are.same({ "id", "name" }, results[2].result_table.headers)
        assert.equals(1, #results[2].result_table.rows)
      end)

      it("should match two SELECT statements", function()
        local statements = {
          { type = "SELECT", text = "SELECT * FROM Users LIMIT 1" },
          { type = "SELECT", text = "SELECT * FROM Products LIMIT 1" }
        }

        local parsed_output = {
          multiple_results = true,
          result_sets = {
            { headers = { "id", "name" }, rows = { { "1", "Alice" } }, metadata = { db_type = "sqlite" } },
            { headers = { "id", "title" }, rows = { { "1", "Widget" } }, metadata = { db_type = "sqlite" } }
          },
          metadata = { db_type = "sqlite" }
        }

        local metadata = {
          execution_time = 8.7,
          row_count = 2,
          db_type = "sqlite"
        }

        local results = matcher.match_statements(statements, parsed_output, metadata)

        assert.equals(2, #results)

        -- First SELECT
        assert.equals("SELECT", results[1].type)
        assert.are.same({ "id", "name" }, results[1].result_table.headers)

        -- Second SELECT
        assert.equals("SELECT", results[2].type)
        assert.are.same({ "id", "title" }, results[2].result_table.headers)
      end)
    end)
  end)

  describe("transaction control statements", function()
    it("should filter out BEGIN and COMMIT statements", function()
      local statements = {
        { type = "UNKNOWN", text = "BEGIN TRANSACTION" },
        { type = "UPDATE", text = "UPDATE users SET status='active' WHERE id=1" },
        { type = "UPDATE", text = "UPDATE users SET status='inactive' WHERE id=2" },
        { type = "UNKNOWN", text = "COMMIT" },
      }

      local parsed_output = {
        headers = {},
        rows = {},
      }

      local metadata = {
        execution_time = 50,
        row_count = 2,
        db_type = "sqlite",
        timestamp = "2024-01-01 12:00:00",
        connection_name = "Test DB",
      }

      local results = matcher.match_statements(statements, parsed_output, metadata)

      -- Should only have 2 results (the UPDATEs), not 4
      assert.equals(2, #results)
      assert.equals("UPDATE", results[1].type)
      assert.equals("UPDATE", results[2].type)
    end)

    it("should filter out ROLLBACK statements", function()
      local statements = {
        { type = "UNKNOWN", text = "BEGIN" },
        { type = "UPDATE", text = "UPDATE users SET status='active' WHERE id=1" },
        { type = "UNKNOWN", text = "ROLLBACK" },
      }

      local parsed_output = {
        headers = {},
        rows = {},
      }

      local metadata = {
        execution_time = 50,
        row_count = 1,
        db_type = "sqlite",
        timestamp = "2024-01-01 12:00:00",
        connection_name = "Test DB",
      }

      local results = matcher.match_statements(statements, parsed_output, metadata)

      -- Should only have 1 result (the UPDATE)
      assert.equals(1, #results)
      assert.equals("UPDATE", results[1].type)
    end)

    it("should recognize transaction control statements", function()
      assert.is_true(matcher._is_transaction_control("BEGIN"))
      assert.is_true(matcher._is_transaction_control("BEGIN TRANSACTION"))
      assert.is_true(matcher._is_transaction_control("START TRANSACTION"))
      assert.is_true(matcher._is_transaction_control("COMMIT"))
      assert.is_true(matcher._is_transaction_control("ROLLBACK"))
      assert.is_true(matcher._is_transaction_control("END TRANSACTION"))
      assert.is_true(matcher._is_transaction_control("END"))

      assert.is_false(matcher._is_transaction_control("SELECT * FROM users"))
      assert.is_false(matcher._is_transaction_control("UPDATE users SET status='active'"))
    end)
  end)
end)

