-- Tests for enhance.nvim explorer module

describe("enhance.explorer", function()
  local explorer
  
  before_each(function()
    -- Reset module state before each test
    package.loaded["enhance.explorer"] = nil
    package.loaded["enhance.connections"] = nil
    
    -- Setup connections
    require("enhance.connections").setup({
      { name = "Test DB", type = "sqlite", path = "/tmp/test.db" }
    })
    
    explorer = require("enhance.explorer")
  end)
  
  describe("get_db_icon", function()
    it("should return correct icon for SQLite", function()
      local icon = explorer._get_db_icon("sqlite")
      assert.is_string(icon)
      assert.is_true(#icon > 0)
    end)
    
    it("should normalize database type names", function()
      -- Test SQL Server variations
      local icon1 = explorer._get_db_icon("SQL Server")
      local icon2 = explorer._get_db_icon("sql-server")
      local icon3 = explorer._get_db_icon("sqlserver")
      local icon4 = explorer._get_db_icon("MSSQL")
      
      -- All should return the same icon
      assert.equals(icon1, icon2)
      assert.equals(icon2, icon3)
      assert.equals(icon3, icon4)
    end)
    
    it("should handle MySQL variations", function()
      local icon1 = explorer._get_db_icon("MySQL")
      local icon2 = explorer._get_db_icon("mysql")
      local icon3 = explorer._get_db_icon("MariaDB")
      
      assert.equals(icon1, icon2)
      assert.equals(icon2, icon3)
    end)
    
    it("should handle PostgreSQL variations", function()
      local icon1 = explorer._get_db_icon("PostgreSQL")
      local icon2 = explorer._get_db_icon("postgres")
      
      assert.equals(icon1, icon2)
    end)
    
    it("should return fallback for unknown database type", function()
      local icon = explorer._get_db_icon("mongodb")
      assert.is_string(icon)
      -- Should return a fallback icon
      assert.is_true(#icon > 0)
    end)
  end)
  
  describe("get_node_icon", function()
    it("should return icon for tables node", function()
      local icon = explorer._get_node_icon("tables")
      assert.is_string(icon)
      assert.equals("󰓱", icon) -- vim-dadbod-ui tables folder icon
    end)
    
    it("should return icon for saved queries node", function()
      local icon = explorer._get_node_icon("saved")
      assert.is_string(icon)
      assert.is_true(#icon > 0, "Should return non-empty icon")
    end)

    it("should return icon for buffers node", function()
      local icon = explorer._get_node_icon("buffer")
      assert.is_string(icon)
      assert.is_true(#icon > 0, "Should return non-empty icon")
    end)

    it("should return icon for new query node", function()
      local icon = explorer._get_node_icon("new_query")
      assert.is_string(icon)
      assert.is_true(#icon > 0, "Should return non-empty icon")
    end)

    it("should return icon for buffer item", function()
      local icon = explorer._get_node_icon("buffer_item")
      assert.is_string(icon)
      assert.is_true(#icon > 0, "Should return non-empty icon")
    end)

    it("should return icon for saved query item", function()
      local icon = explorer._get_node_icon("saved_query")
      assert.is_string(icon)
      assert.is_true(#icon > 0, "Should return non-empty icon")
    end)

    it("should return icon for table item", function()
      local icon = explorer._get_node_icon("table")
      assert.is_string(icon)
      assert.equals("󰓫", icon) -- vim-dadbod-ui table icon
    end)
    
    it("should return fallback for unknown node type", function()
      local icon = explorer._get_node_icon("unknown")
      assert.is_string(icon)
      assert.equals("", icon) -- Fallback icon
    end)
  end)
  
  describe("build_explorer_content", function()
    it("should build header lines", function()
      local lines = explorer._build_explorer_content()

      assert.is_table(lines)
      assert.is_true(#lines >= 2)
      assert.equals("Database Explorer", lines[1])
      assert.equals("", lines[2]) -- Separator line
    end)
    
    it("should include connection in content", function()
      local lines = explorer._build_explorer_content()
      
      -- Should have connection line
      local has_connection = false
      for _, line in ipairs(lines) do
        if line:match("Test DB") then
          has_connection = true
          break
        end
      end
      
      assert.is_true(has_connection, "Should include Test DB connection")
    end)
    
    it("should not include child nodes when connection is collapsed", function()
      local lines = explorer._build_explorer_content()

      -- When collapsed, should NOT have New Query, Buffers, etc.
      local has_new_query = false
      local has_buffers = false

      for _, line in ipairs(lines) do
        if line:match("New Query") then has_new_query = true end
        if line:match("Buffers") then has_buffers = true end
      end

      assert.is_false(has_new_query, "Should not have New Query when collapsed")
      assert.is_false(has_buffers, "Should not have Buffers when collapsed")
    end)
  end)
end)

