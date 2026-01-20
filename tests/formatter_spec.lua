-- Tests for enhance.nvim formatter module

describe("formatter", function()
  local formatter

  before_each(function()
    formatter = require("enhance.formatter")
  end)

  describe("calculate_column_widths", function()
    it("should calculate widths based on headers", function()
      local headers = { "ID", "Name", "Email" }
      local rows = {}
      local config = { min_column_width = 3, max_column_width = 50 }

      local widths = formatter._calculate_column_widths(headers, rows, config)

      assert.are.same({ 3, 4, 5 }, widths)
    end)

    it("should calculate widths based on data", function()
      local headers = { "ID", "Name" }
      local rows = {
        { "1", "Alice" },
        { "2", "Bob" },
        { "3", "Christopher" },
      }
      local config = { min_column_width = 3, max_column_width = 50 }

      local widths = formatter._calculate_column_widths(headers, rows, config)

      assert.are.same({ 3, 11 }, widths)  -- "Christopher" is 11 chars
    end)

    it("should respect max_column_width", function()
      local headers = { "ID", "Description" }
      local rows = {
        { "1", string.rep("x", 100) },
      }
      local config = { min_column_width = 3, max_column_width = 20 }

      local widths = formatter._calculate_column_widths(headers, rows, config)

      assert.are.same({ 3, 20 }, widths)
    end)

    it("should respect min_column_width", function()
      local headers = { "A", "B" }
      local rows = {}
      local config = { min_column_width = 5, max_column_width = 50 }

      local widths = formatter._calculate_column_widths(headers, rows, config)

      assert.are.same({ 5, 5 }, widths)
    end)
  end)

  describe("truncate_value", function()
    it("should not truncate short values", function()
      local result = formatter._truncate_value("Hello", 10, "...")
      assert.equals("Hello", result)
    end)

    it("should truncate long values", function()
      local result = formatter._truncate_value("Hello World", 8, "...")
      assert.equals("Hello...", result)
    end)

    it("should handle width smaller than indicator", function()
      local result = formatter._truncate_value("Hello", 2, "...")
      assert.equals("..", result)
    end)
  end)

  describe("pad_value", function()
    it("should pad short values", function()
      local result = formatter._pad_value("Hi", 5)
      assert.equals("Hi   ", result)
    end)

    it("should not pad values that fit exactly", function()
      local result = formatter._pad_value("Hello", 5)
      assert.equals("Hello", result)
    end)

    it("should not pad values that are too long", function()
      local result = formatter._pad_value("Hello World", 5)
      assert.equals("Hello World", result)
    end)
  end)

  describe("format_row", function()
    it("should format a simple row", function()
      local row = { "1", "Alice", "alice@example.com" }
      local widths = { 3, 5, 17 }
      local config = {
        separator = " | ",
        null_display = "NULL",
        truncate_indicator = "...",
        min_column_width = 3,
      }

      local result = formatter._format_row(row, widths, config)

      assert.equals("| 1   | Alice | alice@example.com |", result)
    end)

    it("should handle NULL values", function()
      local row = { "1", nil, "test" }
      local widths = { 3, 4, 4 }
      local config = {
        separator = " | ",
        null_display = "NULL",
        truncate_indicator = "...",
        min_column_width = 3,
      }

      local result = formatter._format_row(row, widths, config)

      assert.equals("| 1   | NULL | test |", result)
    end)

    it("should truncate long values", function()
      local row = { "1", "Very Long Name That Exceeds Width" }
      local widths = { 3, 10 }
      local config = {
        separator = " | ",
        null_display = "NULL",
        truncate_indicator = "...",
        min_column_width = 3,
      }

      local result = formatter._format_row(row, widths, config)

      assert.equals("| 1   | Very Lo... |", result)
    end)
  end)

  describe("generate_separator", function()
    it("should generate separator line", function()
      local widths = { 3, 5, 10 }
      local config = {
        separator = " | ",
        header_separator_char = "-",
      }

      local result = formatter._generate_separator(widths, config)

      assert.equals("| --- | ----- | ---------- |", result)
    end)
  end)

  describe("format", function()
    it("should format complete result", function()
      local parsed = {
        headers = { "ID", "Name" },
        rows = {
          { "1", "Alice" },
          { "2", "Bob" },
        },
        metadata = { db_type = "sqlite" }
      }

      local lines = formatter.format(parsed)

      assert.equals(4, #lines)
      assert.matches("ID", lines[1])
      assert.matches("Name", lines[1])
      assert.matches("%-%-%-", lines[2])  -- Separator
      assert.matches("Alice", lines[3])
      assert.matches("Bob", lines[4])
    end)

    it("should handle empty results", function()
      local parsed = {
        headers = {},
        rows = {},
        metadata = {}
      }

      local lines = formatter.format(parsed)

      assert.equals(1, #lines)
      assert.equals("No results", lines[1])
    end)
  end)

  describe("format_multiple_statements", function()
    it("should format single SELECT statement", function()
      local statements = {
        {
          type = "SELECT",
          query_text = "SELECT * FROM Users",
          result_table = {
            headers = { "id", "name" },
            rows = { { "1", "Alice" }, { "2", "Bob" } }
          },
          rows = 2,
          elapsed = 12.5,
          db_type = "sqlite",
          db_name = "test.db"
        }
      }

      local lines = formatter.format_multiple_statements(statements)

      -- Should have: header line + separator + 2 data rows (no status line - added by results.display)
      assert.is_true(#lines >= 4)
      assert.is_not_nil(lines[1]:match("id"))
      assert.is_not_nil(lines[1]:match("name"))
      -- Verify we have data rows
      assert.is_not_nil(lines[3]:match("Alice"))
      assert.is_not_nil(lines[4]:match("Bob"))
    end)

    it("should format INSERT statement with message", function()
      local statements = {
        {
          type = "INSERT",
          query_text = "INSERT INTO Users VALUES (1, 'Alice')",
          message = "✓ 1 row inserted",
          rows = 1,
          elapsed = 5.2,
          db_type = "sqlite",
          db_name = "test.db"
        }
      }

      local lines = formatter.format_multiple_statements(statements)

      -- Should have: message line only (no status line - added by results.display)
      assert.is_true(#lines >= 1)
      assert.is_not_nil(lines[1]:match("✓ 1 row inserted"))
    end)

    it("should format two SELECT statements with headers", function()
      local statements = {
        {
          type = "SELECT",
          query_text = "SELECT * FROM Users LIMIT 1",
          result_table = {
            headers = { "id", "name" },
            rows = { { "1", "Alice" } }
          },
          rows = 1,
          elapsed = 8.3,
          db_type = "sqlite",
          db_name = "test.db"
        },
        {
          type = "SELECT",
          query_text = "SELECT * FROM Products LIMIT 1",
          result_table = {
            headers = { "id", "title" },
            rows = { { "1", "Widget" } }
          },
          rows = 1,
          elapsed = 8.3,
          db_type = "sqlite",
          db_name = "test.db"
        }
      }

      local lines = formatter.format_multiple_statements(statements)

      -- Should have result set headers
      local header_found = false
      for _, line in ipairs(lines) do
        if line:match("Result Set 1/2") or line:match("Result Set 2/2") then
          header_found = true
          break
        end
      end
      assert.is_true(header_found, "Should have 'Result Set X/Y' headers")
    end)

    it("should format mixed INSERT and SELECT statements", function()
      local statements = {
        {
          type = "INSERT",
          query_text = "INSERT INTO Users VALUES (1, 'Alice')",
          message = "✓ 1 row inserted",
          rows = 1,
          elapsed = 5.2,
          db_type = "sqlite",
          db_name = "test.db"
        },
        {
          type = "SELECT",
          query_text = "SELECT * FROM Users",
          result_table = {
            headers = { "id", "name" },
            rows = { { "1", "Alice" } }
          },
          rows = 1,
          elapsed = 5.2,
          db_type = "sqlite",
          db_name = "test.db"
        }
      }

      local lines = formatter.format_multiple_statements(statements)

      -- Should have both INSERT message and SELECT table
      local has_insert_message = false
      local has_select_table = false
      for _, line in ipairs(lines) do
        if line:match("✓ 1 row inserted") then
          has_insert_message = true
        end
        if line:match("id") and line:match("name") then
          has_select_table = true
        end
      end
      assert.is_true(has_insert_message, "Should have INSERT message")
      assert.is_true(has_select_table, "Should have SELECT table")
    end)

    it("should separate multiple result sets with blank lines", function()
      local statements = {
        {
          type = "SELECT",
          query_text = "SELECT * FROM Users LIMIT 1",
          result_table = {
            headers = { "id", "name" },
            rows = { { "1", "Alice" } }
          },
          rows = 1,
          elapsed = 8.3,
          db_type = "sqlite",
          db_name = "test.db"
        },
        {
          type = "SELECT",
          query_text = "SELECT * FROM Products LIMIT 1",
          result_table = {
            headers = { "id", "title" },
            rows = { { "1", "Widget" } }
          },
          rows = 1,
          elapsed = 8.3,
          db_type = "sqlite",
          db_name = "test.db"
        }
      }

      local lines = formatter.format_multiple_statements(statements)

      -- Should have at least one blank line separator
      local blank_line_found = false
      for _, line in ipairs(lines) do
        if line == "" then
          blank_line_found = true
          break
        end
      end
      assert.is_true(blank_line_found, "Should have blank line separators between result sets")
    end)

    it("should display individual elapsed time for de-batched statements", function()
      local statements = {
        {
          type = "UPDATE",
          query_text = "UPDATE users SET status='active' WHERE id=1",
          message = "✓ 1 row updated",
          rows = 1,
          elapsed = 12.34,
          db_type = "sqlite",
          db_name = "test.db"
        },
        {
          type = "SELECT",
          query_text = "SELECT * FROM users",
          result_table = {
            headers = { "id", "name" },
            rows = { { "1", "Alice" } }
          },
          rows = 1,
          elapsed = 23.45,
          db_type = "sqlite",
          db_name = "test.db"
        }
      }

      local lines = formatter.format_multiple_statements(statements)

      -- First result set should have elapsed time
      assert.is_not_nil(lines[1]:match("Result Set 1/2"))
      assert.is_not_nil(lines[1]:match("12%.34ms"))

      -- Second result set should have row count BEFORE elapsed time
      local found_second_header = false
      for _, line in ipairs(lines) do
        if line:match("Result Set 2/2") then
          -- Verify order: Rows before elapsed time
          local rows_pos = line:find("Rows:")
          local elapsed_pos = line:find("23%.45ms")
          assert.is_not_nil(rows_pos, "Should have Rows label")
          assert.is_not_nil(elapsed_pos, "Should have elapsed time")
          assert.is_true(rows_pos < elapsed_pos, "Rows should come before elapsed time")
          found_second_header = true
          break
        end
      end
      assert.is_true(found_second_header, "Should find second result set header")
    end)

    it("should not display elapsed time for batched statements", function()
      local statements = {
        {
          type = "UPDATE",
          query_text = "UPDATE users SET status='active' WHERE id=1",
          message = "✓ 1 row updated",
          rows = 1,
          elapsed = 0, -- Batched statement (no individual time)
          db_type = "sqlite",
          db_name = "test.db"
        },
        {
          type = "UPDATE",
          query_text = "UPDATE users SET status='inactive' WHERE id=2",
          message = "✓ 1 row updated",
          rows = 1,
          elapsed = nil, -- Batched statement (no individual time)
          db_type = "sqlite",
          db_name = "test.db"
        }
      }

      local lines = formatter.format_multiple_statements(statements)

      -- First result set should NOT have elapsed time (elapsed = 0)
      assert.is_not_nil(lines[1]:match("Result Set 1/2"))
      assert.is_nil(lines[1]:match("ms"))

      -- Second result set should NOT have elapsed time (elapsed = nil)
      local found_second_header = false
      for _, line in ipairs(lines) do
        if line:match("Result Set 2/2") then
          assert.is_nil(line:match("ms"))
          found_second_header = true
          break
        end
      end
      assert.is_true(found_second_header, "Should find second result set header")
    end)

    it("should handle mixed batched and de-batched statements", function()
      local statements = {
        {
          type = "UPDATE",
          query_text = "UPDATE users SET status='active' WHERE id=1",
          message = "✓ 1 row updated",
          rows = 1,
          elapsed = 12.34, -- De-batched (has individual time)
          db_type = "sqlite",
          db_name = "test.db"
        },
        {
          type = "SELECT",
          query_text = "SELECT * FROM users",
          result_table = {
            headers = { "id", "name" },
            rows = { { "1", "Alice" } }
          },
          rows = 1,
          elapsed = 0, -- Batched (no individual time)
          db_type = "sqlite",
          db_name = "test.db"
        },
        {
          type = "DELETE",
          query_text = "DELETE FROM users WHERE id=1",
          message = "✓ 1 row deleted",
          rows = 1,
          elapsed = 9.88, -- De-batched (has individual time)
          db_type = "sqlite",
          db_name = "test.db"
        }
      }

      local lines = formatter.format_multiple_statements(statements)

      -- First result set should have elapsed time
      assert.is_not_nil(lines[1]:match("Result Set 1/3"))
      assert.is_not_nil(lines[1]:match("12%.34ms"))

      -- Second result set should NOT have elapsed time (batched)
      local found_second = false
      local found_third = false
      for _, line in ipairs(lines) do
        if line:match("Result Set 2/3") then
          assert.is_nil(line:match("ms"))
          found_second = true
        end
        if line:match("Result Set 3/3") then
          assert.is_not_nil(line:match("9%.88ms"))
          found_third = true
        end
      end
      assert.is_true(found_second, "Should find second result set header")
      assert.is_true(found_third, "Should find third result set header")
    end)
  end)
end)

