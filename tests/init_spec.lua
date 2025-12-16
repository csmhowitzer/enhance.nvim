-- Tests for enhance.nvim init module

describe("enhance.init", function()
  local enhance
  
  before_each(function()
    -- Reset module state before each test
    package.loaded["enhance"] = nil
    package.loaded["enhance.init"] = nil
    package.loaded["enhance.connections"] = nil
    enhance = require("enhance")
  end)
  
  describe("default_config", function()
    it("should have correct default values", function()
      local defaults = enhance._default_config
      assert.is_not_nil(defaults)
      assert.is_true(defaults.enabled)
      assert.is_table(defaults.connections)
      assert.equals(0, #defaults.connections)
      assert.is_table(defaults.keymaps)
      assert.equals("<F5>", defaults.keymaps.execute_query)
      assert.is_table(defaults.ui)
      assert.equals("split", defaults.ui.results_position)
      assert.is_true(defaults.ui.show_query_time)
    end)
  end)
  
  describe("setup", function()
    it("should merge user config with defaults", function()
      enhance.setup({
        enabled = false,
        keymaps = {
          execute_query = "<leader>e",
        }
      })
      
      local config = enhance.get_config()
      assert.is_false(config.enabled)
      assert.equals("<leader>e", config.keymaps.execute_query)
      -- Should preserve defaults for unspecified options
      assert.is_table(config.ui)
      assert.equals("split", config.ui.results_position)
    end)
    
    it("should handle nil opts", function()
      enhance.setup(nil)
      local config = enhance.get_config()
      assert.is_not_nil(config)
      assert.is_true(config.enabled)
    end)
    
    it("should handle empty opts", function()
      enhance.setup({})
      local config = enhance.get_config()
      assert.is_not_nil(config)
      assert.is_true(config.enabled)
    end)
    
    it("should merge nested config correctly", function()
      enhance.setup({
        ui = {
          results_position = "vsplit",
        }
      })
      
      local config = enhance.get_config()
      assert.equals("vsplit", config.ui.results_position)
      -- Should preserve other ui defaults
      assert.is_true(config.ui.show_query_time)
    end)
    
    it("should merge connections config", function()
      local test_conns = {
        { name = "Test DB", type = "sqlite", path = "/tmp/test.db" }
      }
      enhance.setup({
        connections = test_conns
      })
      
      local config = enhance.get_config()
      assert.equals(1, #config.connections)
      assert.equals("Test DB", config.connections[1].name)
    end)
    
    it("should return early when enabled is false", function()
      enhance.setup({ enabled = false })
      local config = enhance.get_config()
      assert.is_false(config.enabled)
    end)
    
    it("should create user commands when enabled", function()
      enhance.setup({ enabled = true })
      
      -- Check that commands exist
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.EnhanceToggle)
      assert.is_not_nil(commands.EnhanceStart)
      assert.is_not_nil(commands.EnhanceExplorer)
      assert.is_not_nil(commands.EnhanceResults)
      assert.is_not_nil(commands.EnhanceQuery)
      assert.is_not_nil(commands.EnhanceDeleteFile)
      assert.is_not_nil(commands.EnhanceStop)
    end)
  end)
  
  describe("toggle", function()
    it("should toggle enabled state from true to false", function()
      enhance.setup({ enabled = true })
      assert.is_true(enhance.get_config().enabled)
      
      enhance.toggle()
      assert.is_false(enhance.get_config().enabled)
    end)
    
    it("should toggle enabled state from false to true", function()
      enhance.setup({ enabled = false })
      assert.is_false(enhance.get_config().enabled)
      
      enhance.toggle()
      assert.is_true(enhance.get_config().enabled)
    end)
    
    it("should toggle multiple times", function()
      enhance.setup({ enabled = true })
      
      enhance.toggle()
      assert.is_false(enhance.get_config().enabled)
      
      enhance.toggle()
      assert.is_true(enhance.get_config().enabled)
      
      enhance.toggle()
      assert.is_false(enhance.get_config().enabled)
    end)
  end)
  
  describe("get_config", function()
    it("should return current config", function()
      enhance.setup({
        enabled = true,
        keymaps = {
          execute_query = "<leader>x",
        }
      })
      
      local config = enhance.get_config()
      assert.is_not_nil(config)
      assert.is_true(config.enabled)
      assert.equals("<leader>x", config.keymaps.execute_query)
    end)
    
    it("should return updated config after toggle", function()
      enhance.setup({ enabled = true })
      assert.is_true(enhance.get_config().enabled)
      
      enhance.toggle()
      assert.is_false(enhance.get_config().enabled)
    end)
  end)
end)

