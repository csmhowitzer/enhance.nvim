-- Tests for enhance.nvim SQLite adapter
-- Covers: contract compliance, prepare_query logic, has_error, test_connection, execute_single

describe("enhance.db.sqlite", function()
  local adapter
  local test_db_path

  before_each(function()
    package.loaded["enhance.db.sqlite"] = nil
    adapter = require("enhance.db.sqlite")

    -- Create a temporary database with a known schema
    test_db_path = vim.fn.tempname() .. ".db"
    local init_sql = [[
      CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT, value INTEGER);
      INSERT INTO items VALUES (1, 'alpha', 10);
      INSERT INTO items VALUES (2, 'beta',  20);
      INSERT INTO items VALUES (3, 'gamma', 30);
    ]]
    vim.fn.system(string.format(
      "sqlite3 %s %s",
      vim.fn.shellescape(test_db_path),
      vim.fn.shellescape(init_sql)
    ))
  end)

  after_each(function()
    if test_db_path and vim.fn.filereadable(test_db_path) == 1 then
      vim.fn.delete(test_db_path)
    end
  end)

  -- ----------------------------------------------------------------
  -- Contract compliance
  -- ----------------------------------------------------------------
  describe("adapter contract", function()
    it("exposes supports_debatch as a boolean", function()
      assert.is_boolean(adapter.supports_debatch)
    end)

    it("supports_debatch is true for SQLite", function()
      assert.is_true(adapter.supports_debatch)
    end)

    it("test_connection returns (boolean, string?)", function()
      local ok, err = adapter.test_connection({ path = test_db_path })
      assert.is_boolean(ok)
      if not ok then
        assert.is_string(err)
      end
    end)

    it("prepare_query returns (boolean, string) for SELECT", function()
      local is_dml, exec_q = adapter.prepare_query("SELECT 1")
      assert.is_boolean(is_dml)
      assert.is_string(exec_q)
      assert.is_false(is_dml)
      assert.equals("SELECT 1", exec_q)
    end)

    it("prepare_query returns (boolean, string) for DML", function()
      local is_dml, exec_q = adapter.prepare_query("INSERT INTO t VALUES (1)")
      assert.is_boolean(is_dml)
      assert.is_string(exec_q)
      assert.is_true(is_dml)
    end)

    it("has_error returns boolean for empty lines", function()
      assert.is_boolean(adapter.has_error({}))
    end)

    it("has_error returns boolean for non-empty lines", function()
      assert.is_boolean(adapter.has_error({ "some output line" }))
    end)
  end)

  -- ----------------------------------------------------------------
  -- prepare_query
  -- ----------------------------------------------------------------
  describe("prepare_query", function()
    it("detects INSERT as DML and appends changes()", function()
      local stmt = "INSERT INTO items VALUES (4, 'x', 99)"
      local is_dml, exec_q = adapter.prepare_query(stmt)
      assert.is_true(is_dml)
      assert.equals(stmt .. "; SELECT changes();", exec_q)
    end)

    it("detects UPDATE as DML and appends changes()", function()
      local stmt = "UPDATE items SET value = 0 WHERE id = 1"
      local is_dml, exec_q = adapter.prepare_query(stmt)
      assert.is_true(is_dml)
      assert.equals(stmt .. "; SELECT changes();", exec_q)
    end)

    it("detects DELETE as DML and appends changes()", function()
      local stmt = "DELETE FROM items WHERE id = 1"
      local is_dml, exec_q = adapter.prepare_query(stmt)
      assert.is_true(is_dml)
      assert.equals(stmt .. "; SELECT changes();", exec_q)
    end)

    it("does NOT flag SELECT as DML", function()
      local stmt = "SELECT * FROM items"
      local is_dml, exec_q = adapter.prepare_query(stmt)
      assert.is_false(is_dml)
      assert.equals(stmt, exec_q)
    end)

    it("does NOT flag CREATE as DML", function()
      local is_dml, _ = adapter.prepare_query("CREATE TABLE foo (id INTEGER)")
      assert.is_false(is_dml)
    end)

    it("does NOT flag DROP as DML", function()
      local is_dml, _ = adapter.prepare_query("DROP TABLE foo")
      assert.is_false(is_dml)
    end)

    it("handles leading whitespace in DML statements", function()
      local is_dml, _ = adapter.prepare_query("  \n  INSERT INTO items VALUES (5, 'y', 0)")
      assert.is_true(is_dml)
    end)

    it("is case-insensitive for DML keywords", function()
      local lower_dml, _ = adapter.prepare_query("insert into items values (6, 'z', 0)")
      assert.is_true(lower_dml)
    end)
  end)

  -- ----------------------------------------------------------------
  -- has_error
  -- ----------------------------------------------------------------
  describe("has_error", function()
    it("always returns false for SQLite (errors via exit code)", function()
      assert.is_false(adapter.has_error({}))
      assert.is_false(adapter.has_error({ "Error: no such table: foo" }))
      assert.is_false(adapter.has_error({ "col1", "----", "val1" }))
    end)
  end)

  -- ----------------------------------------------------------------
  -- test_connection
  -- ----------------------------------------------------------------
  describe("test_connection", function()
    it("returns false when database file does not exist", function()
      local ok, err = adapter.test_connection({ path = "/nonexistent/path/db.db" })
      assert.is_false(ok)
      assert.matches("Database file not found", err)
    end)

    it("returns true for a valid SQLite database", function()
      local ok, err = adapter.test_connection({ path = test_db_path })
      assert.is_true(ok)
      assert.is_nil(err)
    end)
  end)

  -- ----------------------------------------------------------------
  -- execute_single
  -- ----------------------------------------------------------------
  describe("execute_single", function()
    local connection

    before_each(function()
      connection = { type = "sqlite", path = test_db_path }
    end)

    it("returns parsed_result, nil, duration, row_count for SELECT", function()
      local result, err, duration, rows = adapter.execute_single(connection, "SELECT * FROM items")
      assert.is_nil(err)
      assert.is_number(duration)
      assert.equals(3, rows)
      assert.is_not_nil(result)
    end)

    it("returns row_count for INSERT (DML)", function()
      local result, err, duration, rows = adapter.execute_single(
        connection, "INSERT INTO items VALUES (99, 'new', 999)"
      )
      assert.is_nil(err)
      assert.is_number(duration)
      assert.equals(1, rows)
    end)

    it("returns row_count for UPDATE (DML)", function()
      local _, err, _, rows = adapter.execute_single(
        connection, "UPDATE items SET value = 0 WHERE value > 0"
      )
      assert.is_nil(err)
      assert.equals(3, rows)
    end)

    it("returns row_count for DELETE (DML)", function()
      local _, err, _, rows = adapter.execute_single(
        connection, "DELETE FROM items WHERE id = 1"
      )
      assert.is_nil(err)
      assert.equals(1, rows)
    end)

    it("returns nil + error_msg on invalid query", function()
      local result, err, duration, rows = adapter.execute_single(
        connection, "SELECT * FROM nonexistent_table_xyz"
      )
      assert.is_nil(result)
      assert.is_string(err)
      assert.is_number(duration)
      assert.equals(0, rows)
    end)
  end)
end)

