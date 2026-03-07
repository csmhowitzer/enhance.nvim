-- tests/db/sqlserver_spec.lua
-- Contract + behavioral tests for the SQL Server database module

local adapter = require("enhance.db.sqlserver")
local parser  = require("enhance.parser")

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
-- ---------------------------------------------------------------------------
-- grammar descriptor — pipeline contract
-- ---------------------------------------------------------------------------
describe("enhance.db.sqlserver grammar", function()
  it("exposes M.grammar as a table", function()
    assert.is_table(adapter.grammar)
  end)

  it("grammar.db_type is 'sqlserver'", function()
    assert.equals("sqlserver", adapter.grammar.db_type)
  end)

  it("grammar.boundary_mode is 'footer'", function()
    assert.equals("footer", adapter.grammar.boundary_mode)
  end)

  it("grammar.boundary_match is a function", function()
    assert.is_function(adapter.grammar.boundary_match)
  end)

  it("grammar.boundary_match matches SQL Server row-count lines", function()
    assert.is_true(adapter.grammar.boundary_match("(1 row affected)"))
    assert.is_true(adapter.grammar.boundary_match("(42 rows affected)"))
    assert.is_true(adapter.grammar.boundary_match("(0 rows affected)"))
    assert.is_false(adapter.grammar.boundary_match("col1  col2"))
    assert.is_false(adapter.grammar.boundary_match(""))
  end)

  it("grammar.row_count_pattern is a string", function()
    assert.is_string(adapter.grammar.row_count_pattern)
  end)

  it("grammar.row_count_pattern captures the numeric count", function()
    local count = ("(7 rows affected)"):match(adapter.grammar.row_count_pattern)
    assert.equals("7", count)
  end)

  it("grammar.parse_chunk is a function", function()
    assert.is_function(adapter.grammar.parse_chunk)
  end)

  it("grammar.include_dml_only is a boolean", function()
    assert.is_boolean(adapter.grammar.include_dml_only)
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

-- ---------------------------------------------------------------------------
-- parse output — behavioral tests via parser.parse(lines, adapter.grammar)
-- ---------------------------------------------------------------------------
describe("enhance.db.sqlserver parse output", function()
  it("parses a basic SELECT result", function()
    local lines = {
      "COLUMN_NAME|DATA_TYPE|CHARACTER_MAXIMUM_LENGTH|IS_NULLABLE",
      "-----------|---------|------------------------|-----------",
      "Id|bigint|NULL|NO",
      "CompanyId|uniqueidentifier|NULL|NO",
      "Key|nvarchar|200|NO",
      "Value|nvarchar|-1|YES",
      "(4 rows affected)",
    }
    local result = parser.parse(lines, adapter.grammar)
    assert.are.same({ "COLUMN_NAME", "DATA_TYPE", "CHARACTER_MAXIMUM_LENGTH", "IS_NULLABLE" }, result.headers)
    assert.equals(4, #result.rows)
    assert.are.same({ "Id", "bigint", "NULL", "NO" }, result.rows[1])
    assert.are.same({ "Value", "nvarchar", "-1", "YES" }, result.rows[4])
    assert.equals("sqlserver", result.metadata.db_type)
  end)

  it("parses empty results (0 rows)", function()
    local lines = { "COLUMN_NAME|DATA_TYPE", "-----------|---------|", "(0 rows affected)" }
    local result = parser.parse(lines, adapter.grammar)
    assert.are.same({ "COLUMN_NAME", "DATA_TYPE" }, result.headers)
    assert.equals(0, #result.rows)
  end)

  it("parses single-column results", function()
    local lines = { "Name", "----", "Alice", "Bob", "(2 rows affected)" }
    local result = parser.parse(lines, adapter.grammar)
    assert.are.same({ "Name" }, result.headers)
    assert.equals(2, #result.rows)
    assert.are.same({ "Alice" }, result.rows[1])
  end)

  it("detects multiple result sets via '(X rows affected)' markers", function()
    local lines = {
      "id|name", "--|----", "1|Alice", "2|Bob", "(2 rows affected)", "",
      "email", "-----", "alice@test.com", "(1 rows affected)",
    }
    local result = parser.parse(lines, adapter.grammar)
    assert.is_true(result.multiple_results)
    assert.equals(2, #result.result_sets)
    assert.are.same({ "id", "name" }, result.result_sets[1].headers)
    assert.equals(2, #result.result_sets[1].rows)
    assert.are.same({ "email" }, result.result_sets[2].headers)
    assert.equals(1, #result.result_sets[2].rows)
  end)

  it("does NOT set multiple_results for a single result set", function()
    local lines = { "id|name", "--|----", "1|Alice", "(1 rows affected)" }
    local result = parser.parse(lines, adapter.grammar)
    assert.is_nil(result.multiple_results)
    assert.are.same({ "id", "name" }, result.headers)
    assert.equals(1, #result.rows)
  end)

  it("extracts row_count from footer markers in each result set", function()
    local lines = {
      "id|name", "--|----", "1|Alice", "2|Bob", "(2 rows affected)", "",
      "email", "-----", "alice@test.com", "(1 rows affected)",
    }
    local result = parser.parse(lines, adapter.grammar)
    assert.equals(2, result.result_sets[1].metadata.row_count)
    assert.equals(1, result.result_sets[2].metadata.row_count)
  end)

  it("extracts row_count for a single result set", function()
    local lines = { "id|name", "--|----", "1|Alice", "(1 rows affected)" }
    local result = parser.parse(lines, adapter.grammar)
    assert.equals(1, result.metadata.row_count)
  end)

  it("replaces blank headers with positional fallbacks", function()
    local lines = { " |Value", "------", "a|test", "(1 rows affected)" }
    local result = parser.parse(lines, adapter.grammar)
    assert.are.same({ "(column-1)", "Value" }, result.headers)
    assert.equals(1, #result.rows)
    assert.are.same({ "a", "test" }, result.rows[1])
  end)
end)
