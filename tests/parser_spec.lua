-- Tests for enhance.nvim parser module

describe("parser", function()
  local parser

  before_each(function()
    parser = require("enhance.parser")
  end)

  describe("normalize_headers", function()
    it("should replace blank headers with default names", function()
      local headers = { "ID", "", "Name", "   ", "Email" }
      local normalized = parser._normalize_headers(headers)

      assert.are.same({ "ID", "(column-2)", "Name", "(column-4)", "Email" }, normalized)
    end)

    it("should preserve non-blank headers", function()
      local headers = { "ID", "Name", "Email" }
      local normalized = parser._normalize_headers(headers)

      assert.are.same({ "ID", "Name", "Email" }, normalized)
    end)

    it("should handle all blank headers", function()
      local headers = { "", "", "" }
      local normalized = parser._normalize_headers(headers)

      assert.are.same({ "(column-1)", "(column-2)", "(column-3)" }, normalized)
    end)
  end)

  describe("parse_sqlserver", function()
    it("should parse SQL Server SELECT output", function()
      local lines = {
        "COLUMN_NAME|DATA_TYPE|CHARACTER_MAXIMUM_LENGTH|IS_NULLABLE",
        "-----------|---------|------------------------|-----------",
        "Id|bigint|NULL|NO",
        "CompanyId|uniqueidentifier|NULL|NO",
        "Key|nvarchar|200|NO",
        "Value|nvarchar|-1|YES",
        "(4 rows affected)",
      }

      local result = parser._parse_sqlserver(lines)

      assert.are.same({ "COLUMN_NAME", "DATA_TYPE", "CHARACTER_MAXIMUM_LENGTH", "IS_NULLABLE" }, result.headers)
      assert.equals(4, #result.rows)
      assert.are.same({ "Id", "bigint", "NULL", "NO" }, result.rows[1])
      assert.are.same({ "Value", "nvarchar", "-1", "YES" }, result.rows[4])
      assert.equals("sqlserver", result.metadata.db_type)
    end)

    it("should handle empty results", function()
      local lines = {
        "COLUMN_NAME|DATA_TYPE",
        "-----------|---------|",
        "(0 rows affected)",
      }

      local result = parser._parse_sqlserver(lines)

      assert.are.same({ "COLUMN_NAME", "DATA_TYPE" }, result.headers)
      assert.equals(0, #result.rows)
    end)

    it("should handle single column", function()
      local lines = {
        "Name",
        "----",
        "Alice",
        "Bob",
        "(2 rows affected)",
      }

      local result = parser._parse_sqlserver(lines)

      assert.are.same({ "Name" }, result.headers)
      assert.equals(2, #result.rows)
      assert.are.same({ "Alice" }, result.rows[1])
    end)

    describe("multiple result sets", function()
      it("should detect multiple result sets via '(X rows affected)' markers", function()
        local lines = {
          "id|name",
          "--|----",
          "1|Alice",
          "2|Bob",
          "(2 rows affected)",
          "",
          "email",
          "-----",
          "alice@test.com",
          "(1 rows affected)",
        }

        local result = parser._parse_sqlserver(lines)

        assert.is_true(result.multiple_results)
        assert.equals(2, #result.result_sets)

        -- First result set
        assert.are.same({ "id", "name" }, result.result_sets[1].headers)
        assert.equals(2, #result.result_sets[1].rows)

        -- Second result set
        assert.are.same({ "email" }, result.result_sets[2].headers)
        assert.equals(1, #result.result_sets[2].rows)
      end)

      it("should NOT set multiple_results for single result set", function()
        local lines = {
          "id|name",
          "--|----",
          "1|Alice",
          "(1 rows affected)",
        }

        local result = parser._parse_sqlserver(lines)

        -- Single result set should NOT have multiple_results flag
        assert.is_nil(result.multiple_results)
        assert.are.same({ "id", "name" }, result.headers)
        assert.equals(1, #result.rows)
      end)
    end)
  end)

  describe("parse_sqlite", function()
    it("should parse SQLite SELECT output", function()
      local lines = {
        "cid  name         type     notnull  dflt_value  pk",
        "---  -----------  -------  -------  ----------  --",
        "0    ID           INTEGER  0                    1 ",
        "1    Name         TEXT     1                    0 ",
        "2    Description  TEXT     0                    0 ",
        "",
      }

      local result = parser._parse_sqlite(lines)

      assert.are.same({ "cid", "name", "type", "notnull", "dflt_value", "pk" }, result.headers)
      assert.equals(3, #result.rows)
      assert.are.same({ "0", "ID", "INTEGER", "0", "", "1" }, result.rows[1])
      assert.equals("sqlite", result.metadata.db_type)
    end)

    it("should handle empty results", function()
      local lines = {
        "id  name",
        "--  ----",
        "",
      }

      local result = parser._parse_sqlite(lines)

      assert.are.same({ "id", "name" }, result.headers)
      assert.equals(0, #result.rows)
    end)

    describe("multiple result sets", function()
      it("should detect single result set (backward compatibility)", function()
        local lines = {
          "id  name ",
          "--  -----",
          "1   Alice",
          "2   Bob  ",
        }

        local result = parser._parse_sqlite(lines)

        -- Single result set should NOT have multiple_results flag
        assert.is_nil(result.multiple_results)
        assert.are.same({ "id", "name" }, result.headers)
        assert.equals(2, #result.rows)
      end)

      it("should detect two result sets with same columns", function()
        local lines = {
          "id  name   email         ",
          "--  -----  --------------",
          "1   Alice  alice@test.com",
          "2   Bob    bob@test.com  ",
          "id  name   email         ",
          "--  -----  --------------",
          "1   Alice  alice@test.com",
        }

        local result = parser._parse_sqlite(lines)

        assert.is_true(result.multiple_results)
        assert.equals(2, #result.result_sets)

        -- First result set
        assert.are.same({ "id", "name", "email" }, result.result_sets[1].headers)
        assert.equals(2, #result.result_sets[1].rows)
        assert.are.same({ "1", "Alice", "alice@test.com" }, result.result_sets[1].rows[1])

        -- Second result set
        assert.are.same({ "id", "name", "email" }, result.result_sets[2].headers)
        assert.equals(1, #result.result_sets[2].rows)
        assert.are.same({ "1", "Alice", "alice@test.com" }, result.result_sets[2].rows[1])
      end)

      it("should detect two result sets with different columns", function()
        local lines = {
          "id  name ",
          "--  -----",
          "1   Alice",
          "2   Bob  ",
          "name   email         ",
          "-----  --------------",
          "Alice  alice@test.com",
        }

        local result = parser._parse_sqlite(lines)

        assert.is_true(result.multiple_results)
        assert.equals(2, #result.result_sets)

        -- First result set
        assert.are.same({ "id", "name" }, result.result_sets[1].headers)
        assert.equals(2, #result.result_sets[1].rows)

        -- Second result set
        assert.are.same({ "name", "email" }, result.result_sets[2].headers)
        assert.equals(1, #result.result_sets[2].rows)
      end)

      it("should detect three result sets", function()
        local lines = {
          "id",
          "--",
          "1 ",
          "name ",
          "-----",
          "Alice",
          "email         ",
          "--------------",
          "alice@test.com",
        }

        local result = parser._parse_sqlite(lines)

        assert.is_true(result.multiple_results)
        assert.equals(3, #result.result_sets)

        assert.are.same({ "id" }, result.result_sets[1].headers)
        assert.equals(1, #result.result_sets[1].rows)

        assert.are.same({ "name" }, result.result_sets[2].headers)
        assert.equals(1, #result.result_sets[2].rows)

        assert.are.same({ "email" }, result.result_sets[3].headers)
        assert.equals(1, #result.result_sets[3].rows)
      end)

      it("should handle empty result set followed by data", function()
        local lines = {
          "id  name",
          "--  ----",
          "id  name ",
          "--  -----",
          "1   Alice",
        }

        local result = parser._parse_sqlite(lines)

        assert.is_true(result.multiple_results)
        assert.equals(2, #result.result_sets)

        -- First result set (empty)
        assert.are.same({ "id", "name" }, result.result_sets[1].headers)
        assert.equals(0, #result.result_sets[1].rows)

        -- Second result set (has data)
        assert.are.same({ "id", "name" }, result.result_sets[2].headers)
        assert.equals(1, #result.result_sets[2].rows)
      end)

      it("should preserve metadata for all result sets", function()
        local lines = {
          "id  name ",
          "--  -----",
          "1   Alice",
          "id  name ",
          "--  -----",
          "2   Bob  ",
        }

        local result = parser._parse_sqlite(lines)

        assert.is_true(result.multiple_results)
        assert.equals("sqlite", result.metadata.db_type)

        -- Each result set should have metadata
        assert.equals("sqlite", result.result_sets[1].metadata.db_type)
        assert.equals("sqlite", result.result_sets[2].metadata.db_type)
      end)
    end)
  end)

  describe("parse_mysql", function()
    it("should parse MySQL SELECT output", function()
      local lines = {
        "+----+-------+",
        "| id | name  |",
        "+----+-------+",
        "|  1 | Alice |",
        "|  2 | Bob   |",
        "+----+-------+",
        "2 rows in set (0.01 sec)",
      }

      local result = parser._parse_mysql(lines)

      assert.are.same({ "id", "name" }, result.headers)
      assert.equals(2, #result.rows)
      assert.are.same({ "1", "Alice" }, result.rows[1])
      assert.are.same({ "2", "Bob" }, result.rows[2])
      assert.equals("mysql", result.metadata.db_type)
    end)

    it("should handle empty results", function()
      local lines = {
        "+----+",
        "| id |",
        "+----+",
        "+----+",
        "0 rows in set (0.00 sec)",
      }

      local result = parser._parse_mysql(lines)

      assert.are.same({ "id" }, result.headers)
      assert.equals(0, #result.rows)
    end)

    describe("multiple result sets", function()
      it("should detect multiple result sets via 'rows in set' markers", function()
        local lines = {
          "+----+-------+",
          "| id | name  |",
          "+----+-------+",
          "|  1 | Alice |",
          "|  2 | Bob   |",
          "+----+-------+",
          "2 rows in set (0.01 sec)",
          "",
          "+----------------+",
          "| email          |",
          "+----------------+",
          "| alice@test.com |",
          "+----------------+",
          "1 rows in set (0.00 sec)",
        }

        local result = parser._parse_mysql(lines)

        assert.is_true(result.multiple_results)
        assert.equals(2, #result.result_sets)

        -- First result set
        assert.are.same({ "id", "name" }, result.result_sets[1].headers)
        assert.equals(2, #result.result_sets[1].rows)

        -- Second result set
        assert.are.same({ "email" }, result.result_sets[2].headers)
        assert.equals(1, #result.result_sets[2].rows)
      end)

      it("should NOT set multiple_results for single result set", function()
        local lines = {
          "+----+-------+",
          "| id | name  |",
          "+----+-------+",
          "|  1 | Alice |",
          "+----+-------+",
          "1 rows in set (0.00 sec)",
        }

        local result = parser._parse_mysql(lines)

        -- Single result set should NOT have multiple_results flag
        assert.is_nil(result.multiple_results)
        assert.are.same({ "id", "name" }, result.headers)
        assert.equals(1, #result.rows)
      end)
    end)
  end)

  describe("parse_postgresql", function()
    it("should parse PostgreSQL SELECT output", function()
      local lines = {
        " id | name  ",
        "----+-------",
        "  1 | Alice",
        "  2 | Bob",
        "(2 rows)",
      }

      local result = parser._parse_postgresql(lines)

      assert.are.same({ "id", "name" }, result.headers)
      assert.equals(2, #result.rows)
      assert.are.same({ "1", "Alice" }, result.rows[1])
      assert.are.same({ "2", "Bob" }, result.rows[2])
      assert.equals("postgresql", result.metadata.db_type)
    end)

    it("should handle empty results", function()
      local lines = {
        " id | name",
        "----+-----",
        "(0 rows)",
      }

      local result = parser._parse_postgresql(lines)

      assert.are.same({ "id", "name" }, result.headers)
      assert.equals(0, #result.rows)
    end)

    describe("multiple result sets", function()
      it("should detect multiple result sets via separator lines", function()
        local lines = {
          " id | name  ",
          "----+-------",
          "  1 | Alice",
          "  2 | Bob",
          "(2 rows)",
          "",
          " email",
          "------",
          " alice@test.com",
          "(1 rows)",
        }

        local result = parser._parse_postgresql(lines)

        assert.is_true(result.multiple_results)
        assert.equals(2, #result.result_sets)

        -- First result set
        assert.are.same({ "id", "name" }, result.result_sets[1].headers)
        assert.equals(2, #result.result_sets[1].rows)

        -- Second result set
        assert.are.same({ "email" }, result.result_sets[2].headers)
        assert.equals(1, #result.result_sets[2].rows)
      end)

      it("should NOT set multiple_results for single result set", function()
        local lines = {
          " id | name",
          "----+-----",
          "  1 | Alice",
          "(1 rows)",
        }

        local result = parser._parse_postgresql(lines)

        -- Single result set should NOT have multiple_results flag
        assert.is_nil(result.multiple_results)
        assert.are.same({ "id", "name" }, result.headers)
        assert.equals(1, #result.rows)
      end)
    end)
  end)

  describe("blank header handling", function()
    it("should handle blank headers in SQL Server output", function()
      local lines = {
        " |Value",
        "------",
        "a|test",
        "(1 rows affected)",
      }

      local result = parser._parse_sqlserver(lines)

      assert.are.same({ "(column-1)", "Value" }, result.headers)
      assert.equals(1, #result.rows)
      assert.are.same({ "a", "test" }, result.rows[1])
    end)

    it("should handle blank headers in SQLite output", function()
      -- SQLite with empty column alias: SELECT 'a' as '';
      -- Produces header line with just whitespace/empty
      local lines = {
        "",  -- Empty header line
        "-",  -- Separator
        "a",  -- Data
      }

      local result = parser._parse_sqlite(lines)

      -- Parser detects 1 column from separator, fills missing header with ""
      -- normalize_headers converts "" to "(column-1)"
      assert.are.same({ "(column-1)" }, result.headers)
      assert.equals(1, #result.rows)
      assert.are.same({ "a" }, result.rows[1])
    end)

    it("should handle blank headers in MySQL output", function()
      local lines = {
        "+-------+",
        "|       |",
        "+-------+",
        "| a     |",
        "+-------+",
      }

      local result = parser._parse_mysql(lines)

      assert.are.same({ "(column-1)" }, result.headers)
      assert.equals(1, #result.rows)
    end)

    it("should handle blank headers in PostgreSQL output", function()
      local lines = {
        "   | name",
        "---+-----",
        " a | Bob",
        "(1 row)",
      }

      local result = parser._parse_postgresql(lines)

      assert.are.same({ "(column-1)", "name" }, result.headers)
      assert.equals(1, #result.rows)
    end)
  end)
end)

