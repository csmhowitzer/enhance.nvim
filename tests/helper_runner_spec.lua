describe('asynchronous helper lifecycle', function()
  local runner, calls, queue, completion, process, deps
  local connection = { server = 'unused', database = 'unused', user = 'reader', password = 'secret-password' }
  local function success()
    return { code = 0, signal = 0, stdout = vim.json.encode({ protocol = 1, ok = true,
      resultSets = {}, messages = {}, errors = {}, affectedRows = vim.NIL, durationMs = 1 }),
      stderr = 'secret-password' }
  end
  local function flush()
    local pending = queue
    queue = {}
    for _, callback in ipairs(pending) do callback() end
  end
  before_each(function()
    calls, queue = {}, {}
    process = { kill = function(_, signal) calls[#calls + 1] = { 'kill', signal } end }
    deps = {
      resolve = function() calls[#calls + 1] = { 'resolve' }; return '/verified/helper' end,
      spawn = function(cmd, opts, callback)
        calls[#calls + 1] = { 'spawn', cmd, opts }
        completion = callback
        return process
      end,
      schedule = function(callback) queue[#queue + 1] = callback end,
    }
  end)
  local function create() runner = require('enhance.helper_runner')._new(deps); return runner end

  it('sends exact SQL and credentials only through stdin, with EOF and a finite deadline', function()
    local received
    local sql = "  SELECT 'a|b';\n-- keep\n"
    create():run(connection, sql, function(result, err) received = { result, err } end)
    assert.equals('resolve', calls[1][1])
    local spawn = calls[2]
    assert.are.same({ '/verified/helper' }, spawn[2])
    assert.is_string(spawn[3].stdin) -- vim.system writes this string and closes stdin.
    assert.equals(sql, vim.json.decode(spawn[3].stdin).query)
    assert.equals('secret-password', vim.json.decode(spawn[3].stdin).connection.password)
    assert.is_false(spawn[3].text)
    assert.is_false(spawn[3].stderr)
    assert.equals(240, vim.json.decode(spawn[3].stdin).commandTimeoutSeconds)
    assert.equals(260000, spawn[3].timeout)
    completion(success())
    assert.is_nil(received)
    flush()
    assert.is_true(received[1].ok)
    assert.is_nil(received[2])
  end)

  it('reports invalid requests before looking up or spawning a helper', function()
    local err
    create():run(connection, ' ', function(_, value) err = value end)
    assert.equals(0, #calls)
    flush()
    assert.equals('Invalid SQL Server helper request', err)
  end)

  it('resolves the PostgreSQL companion by canonical backend without altering parent credentials', function()
    local selected, received
    local parent_password = vim.env.PGPASSWORD
    deps.resolve = function(db) selected = db; return '/verified/postgres' end
    local conn = vim.tbl_extend('force', connection, { type = 'postgres', port = 5433, ssl_mode = 'disable' })
    create():run(conn, 'SELECT 1; SELECT 2', function(result) received = result end)
    assert.equals('postgresql', selected)
    assert.equals('/verified/postgres', calls[1][2][1])
    assert.equals(5433, vim.json.decode(calls[1][3].stdin).connection.port)
    completion(success()); flush()
    assert.equals('postgresql', received.parsed_result.metadata.db_type)
    assert.equals(parent_password, vim.env.PGPASSWORD)
  end)

  it('reports unavailable helpers without installing or echoing resolver diagnostics', function()
    deps.resolve = function() return nil, 'secret-password' end
    local err
    create():run(connection, 'SELECT 1', function(_, value) err = value end)
    assert.equals(0, #calls)
    flush()
    assert.equals('SQL Server helper unavailable; rebuild enhance.nvim in lazy.nvim', err)
  end)

  for _, mode in ipairs({ 'resolve', 'spawn' }) do
    it('handles ' .. mode .. ' exceptions without exposing input or diagnostics', function()
      deps[mode] = function() error('secret-password') end
      local err
      create():run(connection, 'SELECT 1', function(_, value) err = value end)
      flush()
      assert.is_string(err)
      assert.is_nil(err:find('secret-password', 1, true))
    end)
  end

  it('rejects an invalid process handle as startup failure', function()
    deps.spawn = function() return nil end
    local err
    create():run(connection, 'SELECT 1', function(_, value) err = value end)
    flush()
    assert.equals('Failed to start SQL Server helper', err)
  end)

  it('preserves structured query errors rather than turning them into transport failures', function()
    local received
    create():run(connection, 'SELECT 1', function(result, err) received = { result, err } end)
    completion({ code = 1, signal = 0, stdout = vim.json.encode({ protocol = 1, ok = false,
      resultSets = {}, messages = {}, errors = { { kind = 'sql_error', message = 'constraint' } },
      affectedRows = vim.NIL, durationMs = 1 }) })
    flush()
    assert.is_false(received[1].ok)
    assert.is_nil(received[2])
  end)

  for _, case in ipairs({ { 'timeout', 124, 0, 'SQL Server helper timed out' },
    { 'signal', 0, 15, 'SQL Server helper terminated unexpectedly' },
    { 'malformed output', 0, 0, 'Invalid SQL Server helper response' } }) do
    it('handles ' .. case[1] .. ' without raw fallbacks or stderr leakage', function()
      local received, err
      create():run(connection, 'SELECT 1', function(result, value) received, err = result, value end)
      completion({ code = case[2], signal = case[3], stdout = 'secret-password', stderr = 'secret-password' })
      flush()
      assert.is_nil(received)
      assert.equals(case[4], err)
    end)
  end

  it('delivers once even when the exit callback fires twice', function()
    local count = 0
    create():run(connection, 'SELECT 1', function() count = count + 1 end)
    completion(success()); completion(success())
    flush()
    assert.equals(1, count)
  end)

  it('cancels a running process once and ignores its later completion', function()
    local count, err = 0
    create():run(connection, 'SELECT 1', function(_, value) count, err = count + 1, value end)
    assert.is_true(runner:cancel())
    assert.is_false(runner:cancel())
    completion(success())
    flush()
    assert.equals(1, count)
    assert.equals('SQL Server helper cancelled', err)
    assert.are.same({ 'kill', 'sigkill' }, calls[3])
  end)

  it('cancels a scheduled result before delivery without killing an exited process', function()
    local err
    create():run(connection, 'SELECT 1', function(_, value) err = value end)
    completion(success())
    runner:cancel()
    flush()
    assert.equals('SQL Server helper cancelled', err)
    assert.equals(2, #calls)
  end)

  it('suppresses superseded callbacks, including already scheduled results', function()
    local old_count, new_count = 0, 0
    create():run(connection, 'SELECT 1', function() old_count = old_count + 1 end)
    local old_completion = completion
    old_completion(success())
    runner:run(connection, 'SELECT 2', function() new_count = new_count + 1 end)
    completion(success())
    old_completion(success())
    flush()
    assert.equals(0, old_count)
    assert.equals(1, new_count)
  end)

  it('kills an in-flight superseded process without reporting its stale cancellation', function()
    local old_count = 0
    create():run(connection, 'SELECT 1', function() old_count = old_count + 1 end)
    local old_completion = completion
    runner:run(connection, 'SELECT 2', function() end)
    assert.are.same({ 'kill', 'sigkill' }, calls[3])
    old_completion(success())
    flush()
    assert.equals(0, old_count)
  end)

  it('keeps different runner owners independent', function()
    local first_count, second_count = 0, 0
    local first = create()
    first:run(connection, 'SELECT 1', function() first_count = first_count + 1 end)
    local first_completion = completion
    local second = create()
    second:run(connection, 'SELECT 2', function() second_count = second_count + 1 end)
    first_completion(success()); completion(success())
    flush()
    assert.equals(1, first_count)
    assert.equals(1, second_count)
  end)

  it('ignores kill failures without leaking exceptions or delivering twice', function()
    process.kill = function() error('secret-password') end
    local count, err = 0
    create():run(connection, 'SELECT 1', function(_, value) count, err = count + 1, value end)
    runner:cancel()
    completion(success())
    flush()
    assert.equals(1, count)
    assert.equals('SQL Server helper cancelled', err)
  end)

  it('allows a callback to start another request without clearing its ownership', function()
    local count = 0
    create():run(connection, 'SELECT 1', function()
      runner:run(connection, 'SELECT 2', function() count = count + 1 end)
    end)
    completion(success()); flush()
    completion(success()); flush()
    assert.equals(1, count)
  end)

  it('uses validated timeout overrides and rejects invalid process deadlines before spawning', function()
    create():run(connection, 'SELECT 1', function() end, { process_timeout_ms = 1000 })
    assert.equals(1000, calls[2][3].timeout)
    for _, timeout in ipairs({ 0, -1, false, '1000', 1.5 }) do
      calls = {}
      local err
      create():run(connection, 'SELECT 1', function(_, value) err = value end, { process_timeout_ms = timeout })
      flush()
      assert.equals(0, #calls)
      assert.equals('Invalid SQL Server helper process timeout', err)
    end
  end)

  it('keeps an explicit shorter command override and matching process deadline', function()
    create():run(connection, 'SELECT 1', function() end, { command_timeout_seconds = 60 })
    assert.equals(60, vim.json.decode(calls[2][3].stdin).commandTimeoutSeconds)
    assert.equals(80000, calls[2][3].timeout)
  end)

  it('uses only offline cache lookup in the production constructor, never install', function()
    local original_installer = package.loaded['enhance.helper_install']
    local original_system, original_schedule = vim.system, vim.schedule
    local resolved, received = 0
    package.loaded['enhance.helper_install'] = {
      path = function() resolved = resolved + 1; return '/verified/helper' end,
      install = function() error('must not install') end,
    }
    vim.system, vim.schedule = deps.spawn, deps.schedule
    local ok, err = pcall(function()
      local owner = require('enhance.helper_runner').new()
      owner:run(connection, 'SELECT 1', function(value) received = value end)
      completion(success()); flush()
      assert.equals(1, resolved)
      assert.is_true(received.ok)
    end)
    package.loaded['enhance.helper_install'] = original_installer
    vim.system, vim.schedule = original_system, original_schedule
    assert.is_true(ok, tostring(err))
  end)

  local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
  local function real_runner()
    local lifecycle = {}
    local owner = require('enhance.helper_runner')._new({
      resolve = function() return root .. '/tests/fixtures/helper_process.py' end,
      spawn = function(cmd, opts, callback)
        return vim.system({ 'python3', cmd[1] }, opts, function(output)
          lifecycle.exit = output
          callback(output)
        end)
      end,
      schedule = vim.schedule,
    })
    return owner, lifecycle
  end

  it('roundtrips real process stdin/EOF, UTF-8, CR/LF, NULs, and JSON NULL asynchronously', function()
    local done, response, failure = false
    local sql = "  SELECT '雪|value\r\n\0';\n-- unchanged  "
    local owner = real_runner()
    owner:run(connection, sql, function(value, err) done, response, failure = true, value, err end)
    local finished = vim.wait(5000, function() return done end, 10)
    if not finished then owner:cancel() end
    assert.is_true(finished, 'fixture did not finish')
    assert.is_nil(failure)
    assert.equals(sql, response.parsed_result.rows[1][1])
    assert.equals(vim.NIL, response.parsed_result.rows[1][2])
    assert.is_false(owner:cancel())
  end)

  it('terminates a real hung process on cancellation and delivers only once', function()
    local count, failure = 0
    local owner, lifecycle = real_runner()
    owner:run(connection, '__hang__', function(_, err) count, failure = count + 1, err end)
    assert.is_true(owner:cancel())
    assert.is_true(vim.wait(5000, function() return count > 0 end, 10))
    -- Confirm the child really exited, not merely that the UI got cancellation.
    assert.is_true(vim.wait(5000, function() return lifecycle.exit ~= nil end, 10))
    assert.is_true(lifecycle.exit.signal ~= 0 or lifecycle.exit.code ~= 0)
    assert.equals(1, count)
    assert.equals('SQL Server helper cancelled', failure)
  end)

  it('bounds a real hung process with the asynchronous process deadline', function()
    local done, failure = false
    local owner = real_runner()
    owner:run(connection, '__hang__', function(_, err) done, failure = true, err end,
      { process_timeout_ms = 100 })
    local finished = vim.wait(5000, function() return done end, 10)
    if not finished then owner:cancel() end
    assert.is_true(finished, 'process timeout did not finish')
    assert.equals('SQL Server helper timed out', failure)
  end)
end)
