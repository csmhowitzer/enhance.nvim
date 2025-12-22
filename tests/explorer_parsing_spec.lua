-- Tests for enhance.nvim explorer parsing (new string-based parser)

describe("enhance.explorer parsing", function()
  local explorer
  
  before_each(function()
    -- Reset module state before each test
    package.loaded["enhance.explorer"] = nil
    package.loaded["enhance.connections"] = nil
    
    -- Setup test connections with spaces in names
    require("enhance.connections").setup({
      { name = "PostgreSQL Test", type = "postgres", host = "localhost", database = "test", user = "user", port = 5432 },
      { name = "SQLite Test", type = "sqlite", path = "/tmp/test.db" },
      { name = "example.db", type = "sqlite", path = "/tmp/example.db" }
    })
    
    explorer = require("enhance.explorer")
  end)
  
  describe("normalize_name", function()
    it("should replace spaces with underscores", function()
      local normalized = explorer._normalize_name("PostgreSQL Test")
      assert.equals("PostgreSQL_Test", normalized)
    end)
    
    it("should handle names without spaces", function()
      local normalized = explorer._normalize_name("example.db")
      assert.equals("example.db", normalized)
    end)
    
    it("should handle multiple spaces", function()
      local normalized = explorer._normalize_name("My Test Database")
      assert.equals("My_Test_Database", normalized)
    end)
  end)
  
  describe("denormalize_name", function()
    it("should replace underscores with spaces", function()
      local denormalized = explorer._denormalize_name("PostgreSQL_Test")
      assert.equals("PostgreSQL Test", denormalized)
    end)
    
    it("should handle names without underscores", function()
      local denormalized = explorer._denormalize_name("example.db")
      assert.equals("example.db", denormalized)
    end)
  end)
  
  describe("is_arrow", function()
    it("should recognize collapsed arrow", function()
      assert.is_true(explorer._is_arrow("▸"))
    end)
    
    it("should recognize expanded arrow", function()
      assert.is_true(explorer._is_arrow("▾"))
    end)
    
    it("should reject non-arrows", function()
      assert.is_false(explorer._is_arrow("✗"))
      assert.is_false(explorer._is_arrow("✓"))
      assert.is_false(explorer._is_arrow("test"))
    end)
  end)
  
  describe("is_status", function()
    it("should recognize disconnected status", function()
      assert.is_true(explorer._is_status("✗"))
    end)
    
    it("should recognize connected status", function()
      assert.is_true(explorer._is_status("✓"))
    end)
    
    it("should reject non-status symbols", function()
      assert.is_false(explorer._is_status("▸"))
      assert.is_false(explorer._is_status("test"))
    end)
  end)
  
  describe("is_metadata", function()
    it("should recognize metadata with parentheses", function()
      assert.is_true(explorer._is_metadata("(2)"))
      assert.is_true(explorer._is_metadata("(15)"))
    end)
    
    it("should reject non-metadata", function()
      assert.is_false(explorer._is_metadata("test"))
      assert.is_false(explorer._is_metadata("2"))
    end)
  end)
  
  describe("parse_line - connections", function()
    it("should parse disconnected connection with spaces in name", function()
      local line = "✗ ▸ 🐘 PostgreSQL_Test"
      local info = explorer._parse_line(line, 3)
      
      assert.is_table(info)
      assert.equals("connection", info.type)
      assert.equals("PostgreSQL Test", info.conn_name) -- Denormalized
    end)
    
    it("should parse connected connection", function()
      local line = "✓ ▾ 󰆼 example.db"
      local info = explorer._parse_line(line, 3)
      
      assert.is_table(info)
      assert.equals("connection", info.type)
      assert.equals("example.db", info.conn_name)
    end)
    
    it("should parse connection with SQLite Test name", function()
      local line = "✗ ▸ 󰆼 SQLite_Test"
      local info = explorer._parse_line(line, 3)
      
      assert.is_table(info)
      assert.equals("connection", info.type)
      assert.equals("SQLite Test", info.conn_name) -- Denormalized
    end)
  end)
  
  describe("parse_line - child nodes", function()
    it("should parse Buffers node with counter", function()
      -- NOTE: This test requires full explorer buffer context with parent connection
      -- Skipping for now - will be tested in integration tests
      pending("Requires full explorer buffer context with parent connection")
    end)

    it("should parse Tables node", function()
      -- NOTE: This test requires full explorer buffer context with parent connection
      -- Skipping for now - will be tested in integration tests
      pending("Requires full explorer buffer context with parent connection")
    end)

    it("should parse New Query node", function()
      -- NOTE: This test requires full explorer buffer context with parent connection
      -- Skipping for now - will be tested in integration tests
      pending("Requires full explorer buffer context with parent connection")
    end)
  end)
end)

