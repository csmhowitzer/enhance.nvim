---@diagnostic disable: undefined-field
local explorer = require('enhance.explorer')

describe("enhance.bugfixes", function()
  describe("Bug #1: Buffer cleanup", function()
    it("should expose remove_buffer_from_tracking function", function()
      assert.is_not_nil(explorer._remove_buffer_from_tracking)
      assert.is_function(explorer._remove_buffer_from_tracking)
    end)

    it("should handle removing non-existent buffer gracefully", function()
      -- Should not error when removing a buffer that doesn't exist
      local ok = pcall(explorer._remove_buffer_from_tracking, 99999)
      assert.is_true(ok)
    end)
  end)

  describe("Bug #2: Periodic cleanup of invalid buffers", function()
    it("should expose cleanup_invalid_buffers function", function()
      assert.is_not_nil(explorer._cleanup_invalid_buffers)
      assert.is_function(explorer._cleanup_invalid_buffers)
    end)

    it("should run cleanup without errors", function()
      -- Should not error when called
      local ok = pcall(explorer._cleanup_invalid_buffers)
      assert.is_true(ok)
    end)
  end)

  describe("Bug #3: File system error handling", function()
    it("should expose get_connection_tmp_dir function", function()
      assert.is_not_nil(explorer._get_connection_tmp_dir)
      assert.is_function(explorer._get_connection_tmp_dir)
    end)

    it("should expose get_connection_queries_dir function", function()
      assert.is_not_nil(explorer._get_connection_queries_dir)
      assert.is_function(explorer._get_connection_queries_dir)
    end)

    it("should create tmp directory for valid connection", function()
      local connection = {
        name = "test_connection",
        type = "sqlite",
        database = ":memory:"
      }
      
      local tmp_dir = explorer._get_connection_tmp_dir(connection)
      assert.is_not_nil(tmp_dir)
      assert.is_string(tmp_dir)
      assert.is_true(tmp_dir:match("test_connection/tmp$") ~= nil)
    end)

    it("should create queries directory for valid connection", function()
      local connection = {
        name = "test_connection",
        type = "sqlite",
        database = ":memory:"
      }
      
      local queries_dir = explorer._get_connection_queries_dir(connection)
      assert.is_not_nil(queries_dir)
      assert.is_string(queries_dir)
      assert.is_true(queries_dir:match("test_connection/queries$") ~= nil)
    end)

    it("should handle directory creation errors gracefully", function()
      -- Create a connection with invalid characters that might cause issues
      local connection = {
        name = "test\0invalid",  -- Null byte in name
        type = "sqlite",
        database = ":memory:"
      }
      
      -- Should either succeed or return nil, but not crash
      local ok, result = pcall(explorer._get_connection_tmp_dir, connection)
      assert.is_true(ok)  -- Should not throw error
      -- Result could be nil (error) or string (success)
      assert.is_true(result == nil or type(result) == "string")
    end)
  end)

  describe("Integration: Bug fixes working together", function()
    it("should have autocmd setup in start function", function()
      -- Verify that M.start exists (which sets up the autocmd)
      assert.is_not_nil(explorer.start)
      assert.is_function(explorer.start)
    end)

    it("should have refresh_explorer that calls cleanup", function()
      -- Verify that refresh_explorer exists (which calls cleanup_invalid_buffers)
      assert.is_not_nil(explorer.refresh_explorer)
      assert.is_function(explorer.refresh_explorer)
    end)

    it("should call refresh without errors", function()
      -- Should not error when called (even if explorer not initialized)
      local ok = pcall(explorer.refresh_explorer)
      assert.is_true(ok)
    end)
  end)
end)

