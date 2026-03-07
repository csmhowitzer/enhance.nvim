-- tests/db/postgres_spec.lua
-- Contract + behavioral tests for the PostgreSQL database module

local adapter = require("enhance.db.postgres")
local parser  = require("enhance.parser")

-- ---------------------------------------------------------------------------
-- Contract tests — every adapter must satisfy these
-- ---------------------------------------------------------------------------
describe("enhance.db.postgres contract", function()
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

  it("prepare_query returns false for DML (PostgreSQL handles counts natively)", function()
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
describe("enhance.db.postgres build_cmd", function()
  local base = {
    type     = "postgres",
    host     = "db.example.com",
    port     = 5432,
    database = "mydb",
    user     = "pguser",
    password = "secret",
  }

  it("starts with 'psql'", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    assert.equals("psql", cmd[1])
  end)

  it("includes -h for host", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local found = false
    for i, v in ipairs(cmd) do if v == "-h" and cmd[i+1] == "db.example.com" then found = true end end
    assert.is_true(found)
  end)

  it("includes -d for database", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local found = false
    for i, v in ipairs(cmd) do if v == "-d" and cmd[i+1] == "mydb" then found = true end end
    assert.is_true(found)
  end)

  it("includes -p for port", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local found = false
    for i, v in ipairs(cmd) do if v == "-p" and cmd[i+1] == "5432" then found = true end end
    assert.is_true(found)
  end)

  it("includes -U for user", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    local found = false
    for i, v in ipairs(cmd) do if v == "-U" and cmd[i+1] == "pguser" then found = true end end
    assert.is_true(found)
  end)

  it("does NOT include -w when password is set (password goes via env)", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 1;" })
    for _, v in ipairs(cmd) do assert.not_equals("-w", v) end
  end)

  it("includes -w when no password is set", function()
    local conn = { type = "postgres", host = "localhost", database = "mydb", user = "pguser" }
    local cmd = adapter.build_cmd(conn, { query = "SELECT 1;" })
    local found = false
    for _, v in ipairs(cmd) do if v == "-w" then found = true end end
    assert.is_true(found)
  end)

  it("defaults host to localhost when not specified", function()
    local conn = { type = "postgres", database = "mydb", user = "pguser" }
    local cmd = adapter.build_cmd(conn, { query = "SELECT 1;" })
    local found = false
    for i, v in ipairs(cmd) do if v == "-h" and cmd[i+1] == "localhost" then found = true end end
    assert.is_true(found)
  end)

  it("ends with -c and the query string", function()
    local cmd = adapter.build_cmd(base, { query = "SELECT 42;" })
    assert.equals("-c",         cmd[#cmd - 1])
    assert.equals("SELECT 42;", cmd[#cmd])
  end)
end)

-- ---------------------------------------------------------------------------
-- has_error — PostgreSQL uses exit codes, never output scanning
-- ---------------------------------------------------------------------------
describe("enhance.db.postgres has_error", function()
  it("always returns false regardless of output content", function()
    assert.is_false(adapter.has_error({ "ERROR:  relation \"foo\" does not exist" }))
  end)

  it("returns false for empty output", function()
    assert.is_false(adapter.has_error({}))
  end)
end)

-- ---------------------------------------------------------------------------
-- grammar descriptor — pipeline contract
-- ---------------------------------------------------------------------------
describe("enhance.db.postgres grammar", function()
  it("exposes M.grammar as a table", function()
    assert.is_table(adapter.grammar)
  end)

  it("grammar.db_type is 'postgresql'", function()
    assert.equals("postgresql", adapter.grammar.db_type)
  end)

  it("grammar.boundary_mode is 'separator'", function()
    assert.equals("separator", adapter.grammar.boundary_mode)
  end)

  it("grammar.boundary_match is a function", function()
    assert.is_function(adapter.grammar.boundary_match)
  end)

  it("grammar.boundary_match matches PostgreSQL separator lines", function()
    assert.is_true(adapter.grammar.boundary_match("----+-----"))
    assert.is_true(adapter.grammar.boundary_match("----------"))
    assert.is_false(adapter.grammar.boundary_match("col1  col2"))
    assert.is_false(adapter.grammar.boundary_match(""))
  end)

  it("grammar.parse_chunk is a function", function()
    assert.is_function(adapter.grammar.parse_chunk)
  end)
end)

-- ---------------------------------------------------------------------------
-- test_connection — live PostgreSQL (skipped when psql unavailable)
-- ---------------------------------------------------------------------------
describe("enhance.db.postgres test_connection", function()
  local function psql_available()
    vim.fn.system({ "psql", "--version" })
    return vim.v.shell_error ~= 127
  end

  it("returns false for an unreachable server", function()
    if not psql_available() then return end
    local ok, msg = adapter.test_connection({
      type     = "postgres",
      host     = "definitely-not-a-server",
      database = "nonexistent",
      user     = "nobody",
    })
    assert.is_false(ok)
    assert.is_string(msg)
  end)
end)

-- ---------------------------------------------------------------------------
-- parse output — behavioral tests via parser.parse(lines, adapter.grammar)
-- ---------------------------------------------------------------------------
describe("enhance.db.postgres parse output", function()
  it("parses a basic SELECT result", function()
    local lines = {
      " id | name  ",
      "----+-------",
      "  1 | Alice",
      "  2 | Bob",
      "(2 rows)",
    }
    local result = parser.parse(lines, adapter.grammar)
    assert.are.same({ "id", "name" }, result.headers)
    assert.equals(2, #result.rows)
    assert.are.same({ "1", "Alice" }, result.rows[1])
    assert.are.same({ "2", "Bob" }, result.rows[2])
    assert.equals("postgresql", result.metadata.db_type)
  end)

  it("parses empty results (0 rows)", function()
    local lines = {
      " id | name",
      "----+-----",
      "(0 rows)",
    }
    local result = parser.parse(lines, adapter.grammar)
    assert.are.same({ "id", "name" }, result.headers)
    assert.equals(0, #result.rows)
  end)

  it("detects multiple result sets via separator lines", function()
    local lines = {
      " id | name  ",
      "----+-------",
      "  1 | Alice",
      "  2 | Bob",
      "(2 rows)",
      "",
      " email",
      "------",
      " alice@test.com",
      "(1 rows)",
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
    local lines = {
      " id | name",
      "----+-----",
      "  1 | Alice",
      "(1 rows)",
    }
    local result = parser.parse(lines, adapter.grammar)
    assert.is_nil(result.multiple_results)
    assert.are.same({ "id", "name" }, result.headers)
    assert.equals(1, #result.rows)
  end)

  it("replaces blank headers with positional fallbacks", function()
    local lines = {
      "   | name",
      "---+-----",
      " a | Bob",
      "(1 row)",
    }
    local result = parser.parse(lines, adapter.grammar)
    assert.are.same({ "(column-1)", "name" }, result.headers)
    assert.equals(1, #result.rows)
  end)
end)
