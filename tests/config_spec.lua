-- Tests for enhance.nvim configuration module

describe("enhance.config", function()
  local config = require("enhance.config")
  
  describe("defaults", function()
    it("should return default configuration", function()
      local defaults = config.defaults()
      assert.is_not_nil(defaults)
      assert.is_true(defaults.enabled)
      assert.is_table(defaults.connections)
      assert.is_table(defaults.keymaps)
      assert.is_table(defaults.ui)
    end)
  end)
  
  describe("validate_connection", function()
    it("should validate SQLite connection", function()
      local conn = {
        name = "Test DB",
        type = "sqlite",
        path = "/tmp/test.db",
      }
      local valid, err = config._validate_connection(conn)
      assert.is_true(valid)
      assert.is_nil(err)
    end)
    
    it("should reject connection without name", function()
      local conn = {
        type = "sqlite",
        path = "/tmp/test.db",
      }
      local valid, err = config._validate_connection(conn)
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.matches("name is required", err)
    end)
    
    it("should reject connection without type", function()
      local conn = {
        name = "Test DB",
        path = "/tmp/test.db",
      }
      local valid, err = config._validate_connection(conn)
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.matches("type is required", err)
    end)
    
    it("should reject SQLite connection without path", function()
      local conn = {
        name = "Test DB",
        type = "sqlite",
      }
      local valid, err = config._validate_connection(conn)
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.matches("requires 'path'", err)
    end)
  end)
  
  describe("validate_config", function()
    it("should validate config with valid connections", function()
      local cfg = {
        connections = {
          {
            name = "Test DB",
            type = "sqlite",
            path = "/tmp/test.db",
          }
        }
      }
      local valid, err = config._validate_config(cfg)
      assert.is_true(valid)
      assert.is_nil(err)
    end)
    
    it("should reject config with invalid connection", function()
      local cfg = {
        connections = {
          {
            name = "Test DB",
            type = "sqlite",
            -- Missing path
          }
        }
      }
      local valid, err = config._validate_config(cfg)
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.matches("Connection #1", err)
    end)
  end)
  
  describe("merge", function()
    it("should merge user config with defaults", function()
      local user_config = {
        enabled = false,
        keymaps = {
          execute_query = "<leader>e",
        }
      }
      local merged = config.merge(user_config)
      assert.is_false(merged.enabled)
      assert.equals("<leader>e", merged.keymaps.execute_query)
      assert.is_not_nil(merged.ui) -- From defaults
    end)
    
    it("should handle nil user config", function()
      local merged = config.merge(nil)
      assert.is_not_nil(merged)
      assert.is_true(merged.enabled)
    end)
  end)
end)

