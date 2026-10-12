describe('statement execution safety', function()
  local detector = require('enhance.statement_detector')
  local classifier = require('enhance.statement_classifier')

  for _, sql in ipairs({
    'INSERT INTO t VALUES (1)\nSELECT * FROM t',
    'INSERT INTO target SELECT id FROM source',
    'SELECT 1 UNION SELECT 2',
    'SELECT 1\nSELECT 2',
    'CREATE VIEW example AS SELECT 1',
  }) do
    it('keeps undelimited SQL intact: ' .. sql, function()
      local statements = detector.detect_statements(sql)
      assert.equals(1, #statements)
      assert.equals(sql, statements[1].text)
    end)
  end

  it('ignores nested block comments and preserves original SQL', function()
    local sql = "/* outer /* SELECT; */ UPDATE; */ INSERT INTO t VALUES ('a--b'); SELECT 2;"
    local statements = detector.detect_statements(sql)
    assert.equals(2, #statements)
    assert.equals('INSERT', statements[1].type)
    assert.equals("/* outer /* SELECT; */ UPDATE; */ INSERT INTO t VALUES ('a--b')", statements[1].text)
  end)

  it('does not let CASE END close a BEGIN block', function()
    local statements = detector.detect_statements('BEGIN SELECT CASE WHEN 1=1 THEN 1 END; SELECT 2; END; SELECT 3;')
    assert.equals(2, #statements)
    assert.matches('SELECT 2;', statements[1].text)
  end)

  it('does not treat a comment marker inside a string as a real comment', function()
    local statements = detector.detect_statements("SELECT 'a--b'; INSERT INTO t VALUES (1);")
    assert.equals(2, #statements)
  end)

  for _, sql in ipairs({
    'INSERT INTO t VALUES (1)\nSELECT * FROM t',
    'DECLARE @x int = 1; INSERT INTO t VALUES (@x); SELECT @x;',
    'SET NOCOUNT ON; INSERT INTO t VALUES (1);',
    'BEGIN TRAN; UPDATE t SET id=2;',
    'CREATE TEMP TABLE temp_t (id int); INSERT INTO temp_t VALUES (1);',
  }) do
    it('keeps session-dependent SQL batched: ' .. sql, function()
      assert.equals('batch', classifier.classify_for_execution(detector.detect_statements(sql)).execution_mode)
    end)
  end

  it('executes a classifier batch group in one call and retains both result tables', function()
    local executor = require('enhance.executor')
    local adapter = require('enhance.db.sqlite')
    local original_execute = adapter.execute_single
    local original_results = package.loaded['enhance.results']
    local calls, metadata = {}, nil
    adapter.execute_single = function(_, sql)
      calls[#calls + 1] = sql
      return { multiple_results = true, result_sets = {
        { headers = { 'id' }, rows = { { '1' } } },
        { headers = { 'id' }, rows = { { '2' } } },
      } }, nil, 1, 2
    end
    package.loaded['enhance.results'] = { display = function(_, _, _, value) metadata = value end }
    local ok, err = pcall(function()
      executor._execute_debatch_sqlite({ type = 'sqlite', name = 'Safety' }, {
        { type = 'batch', statements = {
          { type = 'SELECT', text = 'SELECT 1 -- trailing comment' },
          { type = 'PRAGMA', text = 'PRAGMA table_info(t)' },
        } },
      })
    end)
    adapter.execute_single = original_execute
    package.loaded['enhance.results'] = original_results
    assert.is_true(ok, tostring(err))
    assert.equals(1, #calls)
    assert.matches('SELECT 1 %-%- trailing comment\n;\nPRAGMA table_info%(t%)', calls[1])
    assert.equals(2, #metadata.statement_results)
    assert.equals('2', metadata.statement_results[2].result_table.rows[1][1])
  end)
end)
