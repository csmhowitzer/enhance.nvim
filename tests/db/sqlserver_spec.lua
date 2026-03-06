-- tests/db/sqlserver_spec.lua
-- Contract + behavioral tests for the SQL Server database module

local adapter = require("enhance.db.sqlserver")

-- ---------------------------------------------------------------------------
-- Contract tests — every adapter must satisfy these
-- ---------------------------------------------------------------------------
describe("enhance.db.sqlserver contract", function()
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

  it("prepare_query returns false for DML (SQL Server handles counts natively)", function()
    local is_dml, exec_q = adapter.prepare_query("INSERT INTO t VALUES (1)")
    assert.is_false(is_dml)
    assert.equals("INSERT INTO t VALUES (1)", exec_q)
  end)

  it("has_error returns a boolean", function()
    assert.is_boolean(adapter.has_error({}))
  end)
end)

-- ---------------------------------------------------------------------------
-- build_cmd — flag generation (deterministic, no live DB needed)
-- ---------------------------------------------------------------------------
describe("enhance.db.sqlserver build_cmd", function()
  local base = {
    type = "sqlserver",
    server = "localhost",
    database = "mydb",
    user = "sa",
    password = "secret",
  }

  it("starts with 'sqlcmd'", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    assert.equals("sqlcmd", cmd[1])
  end)

  it("includes -S for server", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local found = false
    for i, v in ipairs(cmd) do if v == "-S" and cmd[i+1] == "localhost" then found = true end end
    assert.is_true(found)
  end)

  it("includes -d for database", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local found = false
    for i, v in ipairs(cmd) do if v == "-d" and cmd[i+1] == "mydb" then found = true end end
    assert.is_true(found)
  end)

  it("includes -U/-P for SQL auth when user/password provided", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local u, p = false, false
    for i, v in ipairs(cmd) do
      if v == "-U" and cmd[i+1] == "sa"     then u = true end
      if v == "-P" and cmd[i+1] == "secret" then p = true end
    end
    assert.is_true(u)
    assert.is_true(p)
  end)

  it("uses -E (Windows auth) when no user/password", function()
    local conn = { type = "sqlserver", server = "localhost", database = "mydb" }
    local cmd = adapter.build_cmd(conn, { query = "SELECT 1;" })
    local found = false
    for _, v in ipairs(cmd) do if v == "-E" then found = true end end
    assert.is_true(found)
  end)

  it("includes -C by default (trust server certificate)", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local found = false
    for _, v in ipairs(cmd) do if v == "-C" then found = true end end
    assert.is_true(found)
  end)

  it("omits -C when trust_server_certificate = false", function()
    local conn = vim.tbl_extend("force", base, { trust_server_certificate = false })
    local cmd = adapter.build_cmd(conn, { query = "SELECT 1;" })
    for _, v in ipairs(cmd) do
      assert.not_equals("-C", v)
    end
  end)

  it("includes formatting flags by default (-s, -W, -y, 8000)", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local s, W, y = false, false, false
    for i, v in ipairs(cmd) do
      if v == "-s" then s = true end
      if v == "-W" then W = true end
      if v == "-y" and cmd[i+1] == "8000" then y = true end
    end
    assert.is_true(s); assert.is_true(W); assert.is_true(y)
  end)

  it("omits formatting flags when format = false", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;", format = false })
    for _, v in ipairs(cmd) do
      assert.not_equals("-s", v)
      assert.not_equals("-W", v)
    end
  end)

  it("includes -h -1 when no_headers = true", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;", format = false, no_headers = true })
    local found = false
    for i, v in ipairs(cmd) do if v == "-h" and cmd[i+1] == "-1" then found = true end end
    assert.is_true(found)
  end)

  it("ends with -Q and the query string", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 42;" })
    assert.equals("-Q",        cmd[#cmd - 1])
    assert.equals("SELECT 42;", cmd[#cmd])
  end)
end)

-- ---------------------------------------------------------------------------
-- has_error — output pattern detection (no live DB needed)
-- ---------------------------------------------------------------------------
describe("enhance.db.sqlserver has_error", function()
  it("returns true for 'Msg X, Level Y' SQL error lines", function()
    assert.is_true(adapter.has_error({ "Msg 208, Level 16, State 1, Line 1" }))
  end)

  it("returns true when error line is mixed with output", function()
    assert.is_true(adapter.has_error({
      "col1|col2",
      "a|b",
      "Msg 515, Level 16, State 2, Procedure myProc, Line 10",
    }))
  end)

  it("returns false for normal output lines", function()
    assert.is_false(adapter.has_error({ "col1|col2", "a|b", "(1 rows affected)" }))
  end)

  it("returns false for empty output", function()
    assert.is_false(adapter.has_error({}))
  end)

  it("returns false for informational messages that lack the Msg pattern", function()
    assert.is_false(adapter.has_error({ "Warning: some informational message" }))
  end)
end)

-- ---------------------------------------------------------------------------
-- test_connection — live SQL Server (skipped when sqlcmd unavailable)
-- ---------------------------------------------------------------------------
describe("enhance.db.sqlserver test_connection", function()
  local function sqlcmd_available()
    vim.fn.system({ "sqlcmd", "-?" })
    return vim.v.shell_error ~= 127
  end

  it("returns false for an unreachable server", function()
    if not sqlcmd_available() then return end
    local ok, msg = adapter.test_connection({
      type = "sqlserver",
      server = "definitely-not-a-server",
      database = "nonexistent",
      user = "nobody",
      password = "wrong",
    })
    assert.is_false(ok)
    assert.is_string(msg)
  end)
end)

