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

      -- Check that 'r' keymap exists (q was removed - use <C-w>q instead)
      local has_r = false
      for _, map in ipairs(keymaps) do
        if map.lhs == 'r' then
          has_r = true
        end
      end

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

      -- buf1 should have 'r' keymap
      local buf1_has_r = false
      for _, map in ipairs(keymaps1) do
        if map.lhs == 'r' then
          buf1_has_r = true
        end
      end
      assert.is_true(buf1_has_r)

      -- buf2 should not have 'r' keymap
      local buf2_has_r = false
      for _, map in ipairs(keymaps2) do
        if map.lhs == 'r' then
          buf2_has_r = true
        end
      end
      assert.is_false(buf2_has_r)
      
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

  describe("DDL/DML success messages", function()
    local enhance

    before_each(function()
      -- Mock enhance module with config
      package.loaded["enhance"] = {
        get_config = function()
          return {
            format_results = true,
            status_line = {
              enabled = true,
              position = "top",
              highlights = {
                label = "EnhanceStatusLabel",
                value = "EnhanceStatusValue",
                connection = "EnhanceStatusConnection",
                db_type = "EnhanceStatusDBType",
                timestamp = "EnhanceStatusTimestamp",
                separator = "EnhanceStatusSeparator",
                line_number = "EnhanceLineNumber",
                line_number_accent = "EnhanceLineNumberAccent",
              },
            },
            ui = {
              results_position = "split",
              show_query_time = true,
            },
          }
        end,
        setup_highlights = function() end,
      }

      -- Mock explorer module
      package.loaded["enhance.explorer"] = {
        get_results_window = function() return nil end,
        set_results_window = function() end,
      }

      -- Reload results module
      package.loaded["enhance.results"] = nil
      results = require("enhance.results")
    end)

    it("should add success message for CREATE TABLE", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "CREATE_TABLE",
        row_count = 0,
        execution_time = 0.05,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      -- Find the results buffer
      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf, "Should create results buffer")

      -- Get buffer content
      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)

      -- Check for success message
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Table created successfully") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain CREATE TABLE success message")

      -- Cleanup
      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should add success message for DROP TABLE", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "DROP_TABLE",
        row_count = 0,
        execution_time = 0.03,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Table dropped successfully") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain DROP TABLE success message")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should add success message for ALTER TABLE", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "ALTER_TABLE",
        row_count = 0,
        execution_time = 0.04,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Table altered successfully") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain ALTER TABLE success message")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should add success message for INSERT with row count", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "INSERT",
        row_count = 3,
        execution_time = 0.02,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Inserted 3 rows") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain INSERT success message with row count")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should add success message for INSERT with singular row", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "INSERT",
        row_count = 1,
        execution_time = 0.01,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        -- Should be "row" not "rows" for singular
        if line:match("✓ Inserted 1 row") and not line:match("rows") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain INSERT success message with singular 'row'")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should add success message for UPDATE with row count", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "UPDATE",
        row_count = 5,
        execution_time = 0.03,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Updated 5 rows") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain UPDATE success message with row count")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should add success message for DELETE with row count", function()
      local lines = {}
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "DELETE",
        row_count = 2,
        execution_time = 0.02,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Deleted 2 rows") then
          has_message = true
          break
        end
      end

      assert.is_true(has_message, "Should contain DELETE success message with row count")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)

    it("should not add message when there are result rows", function()
      local lines = { "ProductID  Name", "1          Laptop" }
      local connection = { type = "sqlite", name = "test.db" }
      local metadata = {
        query_type = "INSERT",
        row_count = 1,
        execution_time = 0.01,
        db_type = "sqlite",
        timestamp = "12:00:00",
        connection_name = "test.db",
      }

      results.display(lines, connection, nil, metadata)

      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          if ft == "enhance-results" then
            found_buf = buf
            break
          end
        end
      end

      assert.is_not_nil(found_buf)

      local buffer_lines = vim.api.nvim_buf_get_lines(found_buf, 0, -1, false)
      local has_message = false
      for _, line in ipairs(buffer_lines) do
        if line:match("✓ Inserted") then
          has_message = true
          break
        end
      end

      -- Should NOT add message when there are result rows
      assert.is_false(has_message, "Should not add message when result rows exist")

      vim.api.nvim_buf_delete(found_buf, { force = true })
    end)
  end)
end)

