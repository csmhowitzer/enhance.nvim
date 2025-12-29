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
end)

