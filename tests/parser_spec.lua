-- Tests for enhance.nvim parser module
-- DB-specific parse output tests live in tests/db/*_spec.lua

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
end)

