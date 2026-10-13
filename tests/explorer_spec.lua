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

      -- Should have connection line (names are normalized with underscores)
      local has_connection = false
      for _, line in ipairs(lines) do
        if line:match("Test_DB") then
          has_connection = true
          break
        end
      end

      assert.is_true(has_connection, "Should include Test_DB connection")
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

  describe("workspace lifecycle", function()
    local tab, user_buf

    before_each(function()
      vim.cmd("tabnew")
      tab = vim.api.nvim_get_current_tabpage()
      user_buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(user_buf, 0, -1, false, { "unsaved user text" })
    end)

    after_each(function()
      if explorer.is_initialized() then explorer.stop() end
      if vim.api.nvim_tabpage_is_valid(tab) then
        vim.api.nvim_set_current_tabpage(tab)
        vim.bo[user_buf].modified = false
        vim.cmd("tabclose")
      end
    end)

    it("keeps the existing tab, unrelated windows and unsaved text when stopped", function()
      local user_win = vim.api.nvim_get_current_win()
      vim.cmd("vsplit")
      local other_win = vim.api.nvim_get_current_win()
      explorer.start()
      assert.is_true(explorer.is_initialized())
      explorer.stop()
      assert.is_true(vim.api.nvim_tabpage_is_valid(tab))
      assert.is_true(vim.api.nvim_win_is_valid(user_win))
      assert.is_true(vim.api.nvim_win_is_valid(other_win))
      assert.equals(user_buf, vim.api.nvim_win_get_buf(user_win))
      assert.is_true(vim.bo[user_buf].modified)
      assert.equals("unsaved user text", vim.api.nvim_buf_get_lines(user_buf, 0, 1, false)[1])
      assert.is_false(explorer.is_initialized())
    end)

    it("leaves a modified query visible and closes only Enhance's splits", function()
      explorer.start()
      local query_win = vim.api.nvim_get_current_win()
      explorer.open_results()
      assert.is_true(explorer.is_open())
      vim.api.nvim_set_current_win(query_win)
      vim.api.nvim_buf_set_lines(user_buf, 0, -1, false, { "unwritten query" })
      explorer.stop()
      assert.is_true(vim.api.nvim_tabpage_is_valid(tab))
      assert.is_true(vim.api.nvim_win_is_valid(query_win))
      assert.equals(user_buf, vim.api.nvim_win_get_buf(query_win))
      assert.equals("unwritten query", vim.api.nvim_buf_get_lines(user_buf, 0, 1, false)[1])
      assert.is_true(vim.bo[user_buf].modified)
      assert.is_false(explorer.is_open())
    end)

    it("keeps an Enhance split repurposed for a modified user buffer", function()
      explorer.start()
      explorer.open_results()
      local results_win = vim.api.nvim_get_current_win()
      local unsaved = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(results_win, unsaved)
      vim.api.nvim_buf_set_lines(unsaved, 0, -1, false, { "keep this edit" })
      explorer.stop()
      assert.is_true(vim.api.nvim_win_is_valid(results_win))
      assert.equals(unsaved, vim.api.nvim_win_get_buf(results_win))
      assert.is_true(vim.bo[unsaved].modified)
      vim.bo[unsaved].modified = false
      vim.api.nvim_win_close(results_win, false)
      vim.api.nvim_buf_delete(unsaved, { force = true })
    end)

    it("removes its lifecycle autocmds on stop and registers only one set on restart", function()
      explorer.start()
      local first = vim.api.nvim_get_autocmds({ group = "EnhanceExplorerWorkspace" })
      assert.is_true(#first > 0)
      explorer.stop()
      assert.equals(0, #vim.api.nvim_get_autocmds({ group = "EnhanceExplorerWorkspace" }))
      explorer.start()
      assert.equals(#first, #vim.api.nvim_get_autocmds({ group = "EnhanceExplorerWorkspace" }))
      explorer.stop()
      assert.is_true(vim.api.nvim_tabpage_is_valid(tab))
    end)
  end)
end)
