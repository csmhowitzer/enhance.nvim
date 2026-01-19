-- Tests for SQL statement detector
-- Detects individual statements in a SQL query and their types

describe("statement_detector", function()
  local detector

  before_each(function()
    detector = require("enhance.statement_detector")
  end)

  describe("detect_statements", function()
    describe("single statements", function()
      it("should detect single SELECT statement", function()
        local query = "SELECT * FROM Users"
        local statements = detector.detect_statements(query)
        
        assert.equals(1, #statements)
        assert.equals("SELECT", statements[1].type)
        assert.equals("SELECT * FROM Users", statements[1].text)
      end)

      it("should detect single INSERT statement", function()
        local query = "INSERT INTO Users VALUES (1, 'Alice')"
        local statements = detector.detect_statements(query)
        
        assert.equals(1, #statements)
        assert.equals("INSERT", statements[1].type)
      end)

      it("should detect single UPDATE statement", function()
        local query = "UPDATE Users SET name = 'Bob' WHERE id = 1"
        local statements = detector.detect_statements(query)
        
        assert.equals(1, #statements)
        assert.equals("UPDATE", statements[1].type)
      end)

      it("should detect single DELETE statement", function()
        local query = "DELETE FROM Users WHERE id = 1"
        local statements = detector.detect_statements(query)
        
        assert.equals(1, #statements)
        assert.equals("DELETE", statements[1].type)
      end)

      it("should detect single CREATE TABLE statement", function()
        local query = "CREATE TABLE Users (id INT, name TEXT)"
        local statements = detector.detect_statements(query)
        
        assert.equals(1, #statements)
        assert.equals("CREATE", statements[1].type)
      end)

      it("should detect single DROP TABLE statement", function()
        local query = "DROP TABLE Users"
        local statements = detector.detect_statements(query)
        
        assert.equals(1, #statements)
        assert.equals("DROP", statements[1].type)
      end)

      it("should detect single ALTER TABLE statement", function()
        local query = "ALTER TABLE Users ADD COLUMN age INT"
        local statements = detector.detect_statements(query)
        
        assert.equals(1, #statements)
        assert.equals("ALTER", statements[1].type)
      end)
    end)

    describe("semicolon-separated statements", function()
      it("should detect two SELECT statements with semicolon", function()
        local query = "SELECT * FROM Users; SELECT * FROM Products"
        local statements = detector.detect_statements(query)
        
        assert.equals(2, #statements)
        assert.equals("SELECT", statements[1].type)
        assert.equals("SELECT * FROM Users", vim.trim(statements[1].text))
        assert.equals("SELECT", statements[2].type)
        assert.equals("SELECT * FROM Products", vim.trim(statements[2].text))
      end)

      it("should detect mixed statements with semicolons", function()
        local query = "INSERT INTO Users VALUES (1, 'Alice'); SELECT * FROM Users"
        local statements = detector.detect_statements(query)
        
        assert.equals(2, #statements)
        assert.equals("INSERT", statements[1].type)
        assert.equals("SELECT", statements[2].type)
      end)

      it("should detect three statements with semicolons", function()
        local query = "INSERT INTO Users VALUES (1, 'Alice'); UPDATE Users SET name = 'Bob'; SELECT * FROM Users"
        local statements = detector.detect_statements(query)
        
        assert.equals(3, #statements)
        assert.equals("INSERT", statements[1].type)
        assert.equals("UPDATE", statements[2].type)
        assert.equals("SELECT", statements[3].type)
      end)

      it("should handle trailing semicolon", function()
        local query = "SELECT * FROM Users;"
        local statements = detector.detect_statements(query)
        
        assert.equals(1, #statements)
        assert.equals("SELECT", statements[1].type)
      end)

      it("should handle multiple trailing semicolons", function()
        local query = "SELECT * FROM Users;;"
        local statements = detector.detect_statements(query)
        
        assert.equals(1, #statements)
        assert.equals("SELECT", statements[1].type)
      end)
    end)

    describe("newline-separated statements (SQL Server style)", function()
      it("should detect two SELECT statements without semicolons", function()
        local query = [[
SELECT * FROM Users

SELECT * FROM Products
]]
        local statements = detector.detect_statements(query)

        assert.equals(2, #statements)
        assert.equals("SELECT", statements[1].type)
        assert.equals("SELECT", statements[2].type)
      end)

      it("should detect mixed statements without semicolons", function()
        local query = [[
INSERT INTO Users VALUES (1, 'Alice')

SELECT * FROM Users
]]
        local statements = detector.detect_statements(query)

        assert.equals(2, #statements)
        assert.equals("INSERT", statements[1].type)
        assert.equals("SELECT", statements[2].type)
      end)
    end)

    describe("edge cases", function()
      it("should ignore SELECT keyword inside string literals", function()
        local query = "INSERT INTO Users VALUES (1, 'SELECT test')"
        local statements = detector.detect_statements(query)

        assert.equals(1, #statements)
        assert.equals("INSERT", statements[1].type)
      end)

      it("should ignore SELECT keyword inside comments", function()
        local query = [[
-- SELECT test comment
INSERT INTO Users VALUES (1, 'Alice')
]]
        local statements = detector.detect_statements(query)

        assert.equals(1, #statements)
        assert.equals("INSERT", statements[1].type)
      end)

      it("should handle nested subqueries (SELECT inside SELECT)", function()
        local query = "SELECT * FROM (SELECT id FROM Users) AS sub"
        local statements = detector.detect_statements(query)

        assert.equals(1, #statements)
        assert.equals("SELECT", statements[1].type)
        assert.is_true(statements[1].text:find("SELECT id FROM Users") ~= nil)
      end)

      it("should handle complex nested subqueries", function()
        local query = [[
SELECT u.Id, u.Name
FROM Users u
JOIN Orders o ON u.Id = o.UserId
WHERE u.Id IN (SELECT UserId FROM Orders WHERE Total > 100)
]]
        local statements = detector.detect_statements(query)

        assert.equals(1, #statements)
        assert.equals("SELECT", statements[1].type)
      end)

      it("should handle multi-line statements", function()
        local query = [[
SELECT
  id,
  name,
  email
FROM Users
WHERE active = 1
]]
        local statements = detector.detect_statements(query)

        assert.equals(1, #statements)
        assert.equals("SELECT", statements[1].type)
      end)

      it("should handle empty lines between statements", function()
        local query = [[
SELECT * FROM Users


SELECT * FROM Products
]]
        local statements = detector.detect_statements(query)

        assert.equals(2, #statements)
        assert.equals("SELECT", statements[1].type)
        assert.equals("SELECT", statements[2].type)
      end)

      it("should handle case-insensitive keywords", function()
        local query = "select * from Users; INSERT into Products values (1, 'Test')"
        local statements = detector.detect_statements(query)

        assert.equals(2, #statements)
        assert.equals("SELECT", statements[1].type)
        assert.equals("INSERT", statements[2].type)
      end)

      it("should handle whitespace variations", function()
        local query = "  SELECT * FROM Users  ;  INSERT INTO Products VALUES (1, 'Test')  "
        local statements = detector.detect_statements(query)

        assert.equals(2, #statements)
        assert.equals("SELECT", statements[1].type)
        assert.equals("INSERT", statements[2].type)
      end)
    end)
  end)

  describe("contains_transaction_block", function()
    it("should detect BEGIN and COMMIT", function()
      local statements = {
        { type = "UNKNOWN", text = "BEGIN" },
        { type = "UPDATE", text = "UPDATE users SET status='active'" },
        { type = "UNKNOWN", text = "COMMIT" },
      }

      assert.is_true(detector.contains_transaction_block(statements))
    end)

    it("should detect BEGIN TRANSACTION and COMMIT", function()
      local statements = {
        { type = "UNKNOWN", text = "BEGIN TRANSACTION" },
        { type = "UPDATE", text = "UPDATE users SET status='active'" },
        { type = "UNKNOWN", text = "COMMIT" },
      }

      assert.is_true(detector.contains_transaction_block(statements))
    end)

    it("should detect START TRANSACTION and COMMIT", function()
      local statements = {
        { type = "UNKNOWN", text = "START TRANSACTION" },
        { type = "UPDATE", text = "UPDATE users SET status='active'" },
        { type = "UNKNOWN", text = "COMMIT" },
      }

      assert.is_true(detector.contains_transaction_block(statements))
    end)

    it("should detect BEGIN and ROLLBACK", function()
      local statements = {
        { type = "UNKNOWN", text = "BEGIN" },
        { type = "UPDATE", text = "UPDATE users SET status='active'" },
        { type = "UNKNOWN", text = "ROLLBACK" },
      }

      assert.is_true(detector.contains_transaction_block(statements))
    end)

    it("should return false for BEGIN without COMMIT", function()
      local statements = {
        { type = "UNKNOWN", text = "BEGIN" },
        { type = "UPDATE", text = "UPDATE users SET status='active'" },
      }

      assert.is_false(detector.contains_transaction_block(statements))
    end)

    it("should return false for COMMIT without BEGIN", function()
      local statements = {
        { type = "UPDATE", text = "UPDATE users SET status='active'" },
        { type = "UNKNOWN", text = "COMMIT" },
      }

      assert.is_false(detector.contains_transaction_block(statements))
    end)

    it("should return false for regular statements", function()
      local statements = {
        { type = "UPDATE", text = "UPDATE users SET status='active'" },
        { type = "UPDATE", text = "UPDATE users SET status='inactive'" },
      }

      assert.is_false(detector.contains_transaction_block(statements))
    end)

    it("should return false for empty statements", function()
      assert.is_false(detector.contains_transaction_block({}))
    end)

    it("should handle case insensitivity", function()
      local statements = {
        { type = "UNKNOWN", text = "begin" },
        { type = "UPDATE", text = "UPDATE users SET status='active'" },
        { type = "UNKNOWN", text = "commit" },
      }

      assert.is_true(detector.contains_transaction_block(statements))
    end)
  end)
end)

