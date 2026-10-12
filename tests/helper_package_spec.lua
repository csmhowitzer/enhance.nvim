describe('helper release asset packaging', function()
  local root, publish, output
  local script = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h') .. '/scripts/package-helper.py'

  before_each(function()
    root = vim.fn.tempname()
    publish, output = root .. '/publish', root .. '/release'
    vim.fn.mkdir(publish .. '/osx-arm64', 'p')
    local file = assert(io.open(publish .. '/osx-arm64/enhance-helper', 'wb'))
    file:write('a\0b\n')
    file:close()
  end)

  after_each(function()
    -- Delete only the unique fixture directory created by this test.
    vim.fn.delete(root, 'rf')
  end)

  local function run(tag)
    local result = vim.fn.system({ 'python3', script, '--publish-dir', publish,
      '--output-dir', output, '--release', tag or 'helper-v1.0.0' })
    return vim.v.shell_error, result
  end

  it('packages exact binary bytes with a matching pinned manifest', function()
    local code, message = run()
    assert.equals(0, code, message)
    local manifest = vim.json.decode(table.concat(vim.fn.readfile(output .. '/helper-release.json'), '\n'))
    local artifact = manifest.artifacts['osx-arm64']
    assert.equals('helper-v1.0.0', manifest.release)
    assert.equals('enhance-helper-osx-arm64', artifact.name)
    assert.equals('3a100994c4e38751871e6e8eef9adad2b20177fdeaf650daacdcd74f4c9421e3', artifact.sha256)
    assert.equals(artifact.sha256, require('enhance.helper_install')._digest(output .. '/' .. artifact.name))
  end)

  it('packages a PostgreSQL companion under its distinct validated family name', function()
    assert.equals(0, vim.fn.rename(publish .. '/osx-arm64/enhance-helper', publish .. '/osx-arm64/enhance-helper-postgres'))
    local message = vim.fn.system({ 'python3', script, '--publish-dir', publish,
      '--output-dir', output, '--release', 'helper-v1.1.0', '--helper', 'postgres' })
    assert.equals(0, vim.v.shell_error, message)
    local manifest = vim.json.decode(table.concat(vim.fn.readfile(output .. '/helper-release.json'), '\n'))
    assert.equals('postgres', manifest.helper)
    assert.equals('enhance-helper-postgres-osx-arm64', manifest.artifacts['osx-arm64'].name)
  end)

  it('refuses sidecars rather than dropping runtime dependencies', function()
    vim.fn.writefile({ 'native dependency' }, publish .. '/osx-arm64/runtime.dylib')
    local code, message = run()
    assert.equals(1, code)
    assert.matches('sidecars', message)
    assert.equals(0, vim.fn.isdirectory(output))
  end)

  it('refuses to overwrite an existing release', function()
    assert.equals(0, run())
    local code, message = run()
    assert.equals(1, code)
    assert.matches('already exists', message)
  end)

  it('rejects unpinned release names', function()
    local code, message = run('latest')
    assert.equals(1, code)
    assert.matches('immutable', message)
    assert.equals(0, vim.fn.isdirectory(output))
  end)
end)
