-- Tests for JSON column detection in result sets

describe("json_detector", function()
  local detector

  before_each(function()
    detector = require("enhance.json_detector")
  end)

  describe("detect_json_columns", function()
    it("should detect JSON in a single column", function()
      local headers = { "ID", "Name", "Settings" }
      local rows = {
        { "1", "User1", '{"theme": "dark"}' },
        { "2", "User2", '{"theme": "light"}' },
        { "3", "User3", '{"theme": "auto"}' },
      }

      local json_columns = detector.detect_json_columns(headers, rows)

      assert.is_not_nil(json_columns)
      assert.is_false(json_columns[1]) -- ID is not JSON
      assert.is_false(json_columns[2]) -- Name is not JSON
      assert.is_true(json_columns[3])  -- Settings is JSON
    end)

    it("should detect JSON in multiple columns", function()
      local headers = { "ID", "Config", "Metadata" }
      local rows = {
        { "1", '{"key": "value"}', '["tag1", "tag2"]' },
        { "2", '{"key": "value2"}', '["tag3"]' },
      }

      local json_columns = detector.detect_json_columns(headers, rows)

      assert.is_false(json_columns[1]) -- ID is not JSON
      assert.is_true(json_columns[2])  -- Config is JSON
      assert.is_true(json_columns[3])  -- Metadata is JSON
    end)

    it("should only sample first 5 rows by default", function()
      local headers = { "ID", "Data" }
      local rows = {
        { "1", '{"valid": true}' },
        { "2", '{"valid": true}' },
        { "3", '{"valid": true}' },
        { "4", '{"valid": true}' },
        { "5", '{"valid": true}' },
        { "6", "not json" },  -- Row 6 should not be checked
        { "7", "not json" },
        { "8", "not json" },
      }

      local json_columns = detector.detect_json_columns(headers, rows)

      -- Should detect as JSON because first 5 rows are valid JSON
      assert.is_true(json_columns[2])
    end)

    it("should respect custom sample_size parameter", function()
      local headers = { "ID", "Data" }
      local rows = {
        { "1", '{"valid": true}' },
        { "2", '{"valid": true}' },
        { "3", "not json" },  -- Row 3 should be checked with sample_size=3
      }

      local json_columns = detector.detect_json_columns(headers, rows, 3)

      -- Should NOT detect as JSON because row 3 is invalid
      assert.is_false(json_columns[2])
    end)

    it("should handle NULL values gracefully", function()
      local headers = { "ID", "Settings" }
      local rows = {
        { "1", '{"theme": "dark"}' },
        { "2", "" },  -- NULL represented as empty string
        { "3", '{"theme": "light"}' },
      }

      local json_columns = detector.detect_json_columns(headers, rows)

      -- Should still detect as JSON column (NULLs are allowed)
      assert.is_true(json_columns[2])
    end)

    it("should not detect column as JSON if no valid JSON found", function()
      local headers = { "ID", "Name", "Email" }
      local rows = {
        { "1", "John", "john@example.com" },
        { "2", "Jane", "jane@example.com" },
      }

      local json_columns = detector.detect_json_columns(headers, rows)

      assert.is_false(json_columns[1])
      assert.is_false(json_columns[2])
      assert.is_false(json_columns[3])
    end)

    it("should handle empty result set", function()
      local headers = { "ID", "Name" }
      local rows = {}

      local json_columns = detector.detect_json_columns(headers, rows)

      assert.is_not_nil(json_columns)
      assert.is_false(json_columns[1])
      assert.is_false(json_columns[2])
    end)

    it("should handle mixed valid/invalid JSON in sample", function()
      local headers = { "ID", "Data" }
      local rows = {
        { "1", '{"valid": true}' },
        { "2", "not json" },
        { "3", '{"valid": true}' },
      }

      local json_columns = detector.detect_json_columns(headers, rows)

      -- Should NOT detect as JSON if any sampled row is invalid
      assert.is_false(json_columns[2])
    end)

    it("should detect JSON arrays", function()
      local headers = { "ID", "Tags" }
      local rows = {
        { "1", '["tag1", "tag2", "tag3"]' },
        { "2", '["tag4"]' },
      }

      local json_columns = detector.detect_json_columns(headers, rows)

      assert.is_true(json_columns[2])
    end)

    it("should handle nested JSON structures", function()
      local headers = { "ID", "Config" }
      local rows = {
        { "1", '{"user": {"name": "John", "settings": {"theme": "dark"}}}' },
        { "2", '{"user": {"name": "Jane", "settings": {"theme": "light"}}}' },
      }

      local json_columns = detector.detect_json_columns(headers, rows)

      assert.is_true(json_columns[2])
    end)
  end)
end)

