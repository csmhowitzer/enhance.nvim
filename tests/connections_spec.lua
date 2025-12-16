-- Tests for enhance.nvim connections module

describe("enhance.connections", function()
  local connections
  
  before_each(function()
    -- Reset module state before each test
    package.loaded["enhance.connections"] = nil
    connections = require("enhance.connections")
  end)
  
  describe("setup", function()
    it("should add default SQLite connection when no connections provided", function()
      connections.setup({})
      local conns = connections.get_connections()
      assert.equals(1, #conns)
      assert.equals("Test SQLite", conns[1].name)
      assert.equals("sqlite", conns[1].type)
      assert.is_not_nil(conns[1].path)
    end)
    
    it("should add default SQLite connection when nil provided", function()
      connections.setup(nil)
      local conns = connections.get_connections()
      assert.equals(1, #conns)
      assert.equals("Test SQLite", conns[1].name)
    end)
    
    it("should use provided connections", function()
      local test_conns = {
        {
          name = "My DB",
          type = "sqlite",
          path = "/tmp/test.db",
        },
        {
          name = "Another DB",
          type = "postgres",
          host = "localhost",
        }
      }
      connections.setup(test_conns)
      local conns = connections.get_connections()
      assert.equals(2, #conns)
      assert.equals("My DB", conns[1].name)
      assert.equals("Another DB", conns[2].name)
    end)
  end)
  
  describe("get_connections", function()
    it("should return empty list initially", function()
      -- Don't call setup, just get connections
      local conns = connections.get_connections()
      assert.is_table(conns)
    end)
    
    it("should return configured connections", function()
      local test_conns = {
        { name = "DB1", type = "sqlite", path = "/tmp/db1.db" },
        { name = "DB2", type = "sqlite", path = "/tmp/db2.db" },
      }
      connections.setup(test_conns)
      local conns = connections.get_connections()
      assert.equals(2, #conns)
    end)
  end)
  
  describe("get_connection", function()
    before_each(function()
      local test_conns = {
        { name = "DB1", type = "sqlite", path = "/tmp/db1.db" },
        { name = "DB2", type = "postgres", host = "localhost" },
        { name = "DB3", type = "mysql", host = "localhost" },
      }
      connections.setup(test_conns)
    end)
    
    it("should find connection by name", function()
      local conn = connections.get_connection("DB2")
      assert.is_not_nil(conn)
      assert.equals("DB2", conn.name)
      assert.equals("postgres", conn.type)
    end)
    
    it("should return nil for non-existent connection", function()
      local conn = connections.get_connection("NonExistent")
      assert.is_nil(conn)
    end)
    
    it("should find first connection", function()
      local conn = connections.get_connection("DB1")
      assert.is_not_nil(conn)
      assert.equals("sqlite", conn.type)
    end)
    
    it("should find last connection", function()
      local conn = connections.get_connection("DB3")
      assert.is_not_nil(conn)
      assert.equals("mysql", conn.type)
    end)
  end)
  
  describe("set_current and get_current", function()
    local test_conn
    
    before_each(function()
      test_conn = {
        name = "Test DB",
        type = "sqlite",
        path = "/tmp/test.db",
      }
    end)
    
    it("should return nil initially", function()
      local current = connections.get_current()
      assert.is_nil(current)
    end)
    
    it("should set and get current connection", function()
      connections.set_current(test_conn)
      local current = connections.get_current()
      assert.is_not_nil(current)
      assert.equals("Test DB", current.name)
      assert.equals("sqlite", current.type)
    end)
    
    it("should update current connection", function()
      local conn1 = { name = "DB1", type = "sqlite", path = "/tmp/db1.db" }
      local conn2 = { name = "DB2", type = "postgres", host = "localhost" }
      
      connections.set_current(conn1)
      assert.equals("DB1", connections.get_current().name)
      
      connections.set_current(conn2)
      assert.equals("DB2", connections.get_current().name)
    end)
  end)
end)

