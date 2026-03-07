-- tests/db/mysql_spec.lua
-- Contract + behavioral tests for the MySQL database module

local adapter = require("enhance.db.mysql")
local parser  = require("enhance.parser")

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
-- grammar descriptor — pipeline contract
-- ---------------------------------------------------------------------------
describe("enhance.db.mysql grammar", function()
  it("exposes M.grammar as a table", function()
    assert.is_table(adapter.grammar)
  end)

  it("grammar.db_type is 'mysql'", function()
    assert.equals("mysql", adapter.grammar.db_type)
  end)

  it("grammar.boundary_mode is 'footer'", function()
    assert.equals("footer", adapter.grammar.boundary_mode)
  end)

  it("grammar.boundary_match is a function", function()
    assert.is_function(adapter.grammar.boundary_match)
  end)

  it("grammar.boundary_match matches MySQL 'rows in set' lines", function()
    assert.is_true(adapter.grammar.boundary_match("1 row in set (0.00 sec)"))
    assert.is_true(adapter.grammar.boundary_match("42 rows in set (0.01 sec)"))
    assert.is_true(adapter.grammar.boundary_match("0 rows in set"))
    assert.is_false(adapter.grammar.boundary_match("col1  col2"))
    assert.is_false(adapter.grammar.boundary_match(""))
  end)

  it("grammar.parse_chunk is a function", function()
    assert.is_function(adapter.grammar.parse_chunk)
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

-- ---------------------------------------------------------------------------
-- parse output — behavioral tests via parser.parse(lines, adapter.grammar)
-- ---------------------------------------------------------------------------
describe("enhance.db.mysql parse output", function()
  it("parses a basic SELECT result", function()
    local lines = {
      "+----+-------+",
      "| id | name  |",
      "+----+-------+",
      "|  1 | Alice |",
      "|  2 | Bob   |",
      "+----+-------+",
      "2 rows in set (0.01 sec)",
    }
    local result = parser.parse(lines, adapter.grammar)
    assert.are.same({ "id", "name" }, result.headers)
    assert.equals(2, #result.rows)
    assert.are.same({ "1", "Alice" }, result.rows[1])
    assert.are.same({ "2", "Bob" }, result.rows[2])
    assert.equals("mysql", result.metadata.db_type)
  end)

  it("parses empty results (0 rows)", function()
    local lines = {
      "+----+",
      "| id |",
      "+----+",
      "+----+",
      "0 rows in set (0.00 sec)",
    }
    local result = parser.parse(lines, adapter.grammar)
    assert.are.same({ "id" }, result.headers)
    assert.equals(0, #result.rows)
  end)

  it("detects multiple result sets via 'rows in set' markers", function()
    local lines = {
      "+----+-------+",
      "| id | name  |",
      "+----+-------+",
      "|  1 | Alice |",
      "|  2 | Bob   |",
      "+----+-------+",
      "2 rows in set (0.01 sec)",
      "",
      "+----------------+",
      "| email          |",
      "+----------------+",
      "| alice@test.com |",
      "+----------------+",
      "1 rows in set (0.00 sec)",
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
      "+----+-------+",
      "| id | name  |",
      "+----+-------+",
      "|  1 | Alice |",
      "+----+-------+",
      "1 rows in set (0.00 sec)",
    }
    local result = parser.parse(lines, adapter.grammar)
    assert.is_nil(result.multiple_results)
    assert.are.same({ "id", "name" }, result.headers)
    assert.equals(1, #result.rows)
  end)

  it("replaces blank headers with positional fallbacks", function()
    local lines = {
      "+-------+",
      "|       |",
      "+-------+",
      "| a     |",
      "+-------+",
    }
    local result = parser.parse(lines, adapter.grammar)
    assert.are.same({ "(column-1)" }, result.headers)
    assert.equals(1, #result.rows)
  end)
end)
