-- Tests for enhance.nvim results module

describe("enhance.results", function()
  local results
  
  before_each(function()
    -- Reset module state before each test
    package.loaded["enhance.results"] = nil
    results = require("enhance.results")
  end)
  
  describe("setup_keymaps", function()
    it("should set up keymaps for results buffer", function()
      -- Create a test buffer
      local buf = vim.api.nvim_create_buf(false, true)
      
      -- Setup keymaps
      results._setup_keymaps(buf)
      
      -- Verify buffer is valid
      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      
      -- Get buffer keymaps
      local keymaps = vim.api.nvim_buf_get_keymap(buf, 'n')
      
      -- Check that 'q' and 'r' keymaps exist
      local has_q = false
      local has_r = false
      for _, map in ipairs(keymaps) do
        if map.lhs == 'q' then
          has_q = true
        end
        if map.lhs == 'r' then
          has_r = true
        end
      end
      
      assert.is_true(has_q, "Should have 'q' keymap")
      assert.is_true(has_r, "Should have 'r' keymap")
      
      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
    
    it("should set keymaps only for specific buffer", function()
      local buf1 = vim.api.nvim_create_buf(false, true)
      local buf2 = vim.api.nvim_create_buf(false, true)
      
      -- Setup keymaps only for buf1
      results._setup_keymaps(buf1)
      
      -- Get keymaps for both buffers
      local keymaps1 = vim.api.nvim_buf_get_keymap(buf1, 'n')
      local keymaps2 = vim.api.nvim_buf_get_keymap(buf2, 'n')
      
      -- buf1 should have keymaps
      local buf1_has_q = false
      for _, map in ipairs(keymaps1) do
        if map.lhs == 'q' then
          buf1_has_q = true
        end
      end
      assert.is_true(buf1_has_q)
      
      -- buf2 should not have keymaps
      local buf2_has_q = false
      for _, map in ipairs(keymaps2) do
        if map.lhs == 'q' then
          buf2_has_q = true
        end
      end
      assert.is_false(buf2_has_q)
      
      -- Cleanup
      vim.api.nvim_buf_delete(buf1, { force = true })
      vim.api.nvim_buf_delete(buf2, { force = true })
    end)
  end)
  
  describe("display_message", function()
    it("should create a buffer with message content", function()
      local test_lines = {
        "Error: Connection failed",
        "Please check your database configuration"
      }
      
      -- Mock explorer module to avoid dependencies
      package.loaded["enhance.explorer"] = {
        get_results_window = function() return nil end,
        set_results_window = function() end,
      }
      
      -- Display message
      results.display_message(test_lines)
      
      -- Find the message buffer
      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local name = vim.api.nvim_buf_get_name(buf)
          if name:match("%[Enhance%] Message") then
            found_buf = buf
            break
          end
        end
      end
      
      assert.is_not_nil(found_buf, "Should create message buffer")
      
      -- Verify buffer properties
      assert.equals('enhance-results', vim.bo[found_buf].filetype)
      assert.is_false(vim.bo[found_buf].modifiable)
      
      -- Verify content
      local lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      assert.equals(2, #lines)
      assert.equals("Error: Connection failed", lines[1])
      assert.equals("Please check your database configuration", lines[2])
      
      -- Cleanup
      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)
    
    it("should set buffer as non-modifiable", function()
      local test_lines = { "Test message" }
      
      -- Mock explorer module
      package.loaded["enhance.explorer"] = {
        get_results_window = function() return nil end,
        set_results_window = function() end,
      }
      
      results.display_message(test_lines)
      
      -- Find the message buffer
      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local name = vim.api.nvim_buf_get_name(buf)
          if name:match("%[Enhance%] Message") then
            found_buf = buf
            break
          end
        end
      end
      
      assert.is_not_nil(found_buf)
      assert.is_false(vim.bo[found_buf].modifiable)
      
      -- Cleanup
      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)
  end)
end)

