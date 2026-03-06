-- tests/db/mysql_spec.lua
-- Contract + behavioral tests for the MySQL database module

local adapter = require("enhance.db.mysql")

-- ---------------------------------------------------------------------------
-- Contract tests — every adapter must satisfy these
-- ---------------------------------------------------------------------------
describe("enhance.db.mysql contract", function()
  it("exposes supports_debatch as a boolean", function()
    assert.is_boolean(adapter.supports_debatch)
  end)

  it("exposes build_cmd as a function", function()
    assert.is_function(adapter.build_cmd)
  end)

  it("exposes prepare_query as a function", function()
    assert.is_function(adapter.prepare_query)
  end)

  it("exposes has_error as a function", function()
    assert.is_function(adapter.has_error)
  end)

  it("exposes test_connection as a function", function()
    assert.is_function(adapter.test_connection)
  end)

  it("exposes execute_single as a function", function()
    assert.is_function(adapter.execute_single)
  end)

  it("prepare_query returns (boolean, string) and never rewrites the query", function()
    local is_dml, exec_q = adapter.prepare_query("SELECT 1")
    assert.is_boolean(is_dml)
    assert.is_string(exec_q)
    assert.is_false(is_dml)
    assert.equals("SELECT 1", exec_q)
  end)

  it("prepare_query returns false for DML (MySQL handles counts natively)", function()
    local is_dml, exec_q = adapter.prepare_query("DELETE FROM t WHERE id = 1")
    assert.is_false(is_dml)
    assert.equals("DELETE FROM t WHERE id = 1", exec_q)
  end)

  it("has_error returns a boolean", function()
    assert.is_boolean(adapter.has_error({}))
  end)
end)

-- ---------------------------------------------------------------------------
-- build_cmd — flag generation (no live DB needed)
-- ---------------------------------------------------------------------------
describe("enhance.db.mysql build_cmd", function()
  local base = {
    type     = "mysql",
    host     = "db.example.com",
    port     = 3306,
    database = "mydb",
    user     = "root",
    password = "secret",
  }

  it("starts with 'mysql'", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    assert.equals("mysql", cmd[1])
  end)

  it("includes -h for host", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local found = false
    for i, v in ipairs(cmd) do if v == "-h" and cmd[i+1] == "db.example.com" then found = true end end
    assert.is_true(found)
  end)

  it("includes -P for port", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local found = false
    for i, v in ipairs(cmd) do if v == "-P" and cmd[i+1] == "3306" then found = true end end
    assert.is_true(found)
  end)

  it("includes -u for user", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local found = false
    for i, v in ipairs(cmd) do if v == "-u" and cmd[i+1] == "root" then found = true end end
    assert.is_true(found)
  end)

  it("appends -p<password> with no space", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local found = false
    for _, v in ipairs(cmd) do if v == "-psecret" then found = true end end
    assert.is_true(found)
  end)

  it("omits -h when host is not set", function()
    local conn = { type = "mysql", database = "mydb", user = "root" }
    local cmd = adapter.build_cmd(conn, { query = "SELECT 1;" })
    for _, v in ipairs(cmd) do assert.not_equals("-h", v) end
  end)

  it("includes database as positional arg before -e", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    -- database should appear before -e
    local db_pos, e_pos = nil, nil
    for i, v in ipairs(cmd) do
      if v == "mydb"  then db_pos = i end
      if v == "-e"    then e_pos  = i end
    end
    assert.is_not_nil(db_pos)
    assert.is_not_nil(e_pos)
    assert.is_true(db_pos < e_pos)
  end)

  it("ends with -e and the query string", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 42;" })
    assert.equals("-e",         cmd[#cmd - 1])
    assert.equals("SELECT 42;", cmd[#cmd])
  end)
end)

-- ---------------------------------------------------------------------------
-- has_error — MySQL uses exit codes, never output scanning
-- ---------------------------------------------------------------------------
describe("enhance.db.mysql has_error", function()
  it("always returns false regardless of output content", function()
    assert.is_false(adapter.has_error({ "ERROR 1045 (28000): Access denied" }))
  end)

  it("returns false for empty output", function()
    assert.is_false(adapter.has_error({}))
  end)
end)

-- ---------------------------------------------------------------------------
-- test_connection — live MySQL (skipped when mysql unavailable)
-- ---------------------------------------------------------------------------
describe("enhance.db.mysql test_connection", function()
  local function mysql_available()
    vim.fn.system({ "mysql", "--version" })
    return vim.v.shell_error ~= 127
  end

  it("returns false for an unreachable server", function()
    if not mysql_available() then return end
    local ok, msg = adapter.test_connection({
      type     = "mysql",
      host     = "definitely-not-a-server",
      database = "nonexistent",
      user     = "nobody",
      password = "wrong",
    })
    assert.is_false(ok)
    assert.is_string(msg)
  end)
end)

