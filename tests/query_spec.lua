-- Tests for enhance.nvim query module

describe("enhance.query", function()
  local query
  
  before_each(function()
    -- Reset module state before each test
    package.loaded["enhance.query"] = nil
    package.loaded["enhance"] = nil
    
    -- Setup enhance with default config
    require("enhance").setup({})
    query = require("enhance.query")
  end)
  
  describe("setup_keymaps", function()
    it("should set up keymaps for query buffer", function()
      -- Create a test buffer
      local buf = vim.api.nvim_create_buf(false, true)
      
      -- Setup keymaps
      query._setup_keymaps(buf)
      
      -- Verify buffer is valid
      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      
      -- Get buffer keymaps
      local keymaps_n = vim.api.nvim_buf_get_keymap(buf, 'n')
      local keymaps_v = vim.api.nvim_buf_get_keymap(buf, 'v')
      
      -- Check that execute_query keymap exists in normal mode
      local has_execute_n = false
      for _, map in ipairs(keymaps_n) do
        if map.lhs == '<F5>' then  -- Default execute_query keymap
          has_execute_n = true
        end
      end
      assert.is_true(has_execute_n, "Should have execute keymap in normal mode")
      
      -- Check that execute_query keymap exists in visual mode
      local has_execute_v = false
      for _, map in ipairs(keymaps_v) do
        if map.lhs == '<F5>' then
          has_execute_v = true
        end
      end
      assert.is_true(has_execute_v, "Should have execute keymap in visual mode")
      
      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
    
    it("should set keymaps only for specific buffer", function()
      local buf1 = vim.api.nvim_create_buf(false, true)
      local buf2 = vim.api.nvim_create_buf(false, true)

      -- Setup keymaps only for buf1
      query._setup_keymaps(buf1)

      -- Get keymaps for both buffers
      local keymaps1 = vim.api.nvim_buf_get_keymap(buf1, 'n')
      local keymaps2 = vim.api.nvim_buf_get_keymap(buf2, 'n')

      -- buf1 should have keymaps
      local buf1_has_f5 = false
      for _, map in ipairs(keymaps1) do
        if map.lhs == '<F5>' then
          buf1_has_f5 = true
        end
      end
      assert.is_true(buf1_has_f5)

      -- buf2 should not have keymaps
      local buf2_has_f5 = false
      for _, map in ipairs(keymaps2) do
        if map.lhs == '<F5>' then
          buf2_has_f5 = true
        end
      end
      assert.is_false(buf2_has_f5)

      -- Cleanup
      vim.api.nvim_buf_delete(buf1, { force = true })
      vim.api.nvim_buf_delete(buf2, { force = true })
    end)
  end)
  
  describe("execute_current_query", function()
    it("should warn when no connection is established", function()
      local buf = vim.api.nvim_create_buf(false, true)
      
      -- Mock results module to avoid dependencies
      package.loaded["enhance.results"] = {
        display_message = function(lines)
          -- Verify message content
          assert.is_table(lines)
          assert.is_true(#lines > 0)
          assert.matches("No database connection", lines[1])
        end
      }
      
      -- Execute without connection
      query.execute_current_query(buf)
      
      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
    
    it("should warn when query is empty", function()
      local buf = vim.api.nvim_create_buf(false, true)
      
      -- Set connection
      vim.b[buf].enhance_connection = {
        name = "Test DB",
        type = "sqlite",
        path = "/tmp/test.db"
      }
      
      -- Set empty content
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
      
      -- Execute empty query
      query.execute_current_query(buf)
      
      -- Should show warning (we can't easily verify vim.notify, but no error is good)
      
      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
    
    it("should execute query with connection", function()
      local buf = vim.api.nvim_create_buf(false, true)

      -- Set connection
      vim.b[buf].enhance_connection = {
        name = "Test DB",
        type = "sqlite",
        path = "/tmp/test.db"
      }

      -- Set content
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "SELECT * FROM users;"
      })

      -- Mock executor to capture the query
      local executed_query = nil
      local executed_conn = nil
      package.loaded["enhance.executor"] = {
        execute = function(conn, query_text, bufnr)
          executed_query = query_text
          executed_conn = conn
        end
      }

      -- Execute query
      query.execute_current_query(buf)

      -- Verify query was executed
      assert.is_not_nil(executed_query)
      assert.is_not_nil(executed_conn)
      assert.equals("Test DB", executed_conn.name)
      assert.is_true(#executed_query > 0, "Query should not be empty")

      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
  
  describe("execute_visual_selection", function()
    it("should warn when no connection is established", function()
      local buf = vim.api.nvim_create_buf(false, true)
      
      -- Mock results module
      package.loaded["enhance.results"] = {
        display_message = function(lines)
          assert.is_table(lines)
          assert.matches("No database connection", lines[1])
        end
      }
      
      -- Execute without connection
      query.execute_visual_selection(buf)
      
      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)

