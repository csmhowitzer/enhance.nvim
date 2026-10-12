describe('helper release installation', function()
  local available, module = pcall(require, 'enhance.helper_install')
  if not available then
    it('provides the helper installer', function() assert.is_true(available, tostring(module)) end)
    return
  end
  local installer, manifest, ops, files, downloads, removed
  local hash = string.rep('a', 64)

  before_each(function()
    installer = require('enhance.helper_install')
    manifest = { schema = 1, release = 'helper-v1.0.0', artifacts = {
      ['osx-arm64'] = { name = 'enhance-helper-osx-arm64', sha256 = hash },
    } }
    files, downloads, removed = {}, {}, {}
    ops = {
      platform = 'osx-arm64', root = '/cache/enhance/helper',
      exists = function(path) return files[path] ~= nil end,
      digest = function(path) return files[path] end,
      mkdir = function() end,
      lock = function() return true end,
      unlock = function() end,
      download = function(url, path) downloads[#downloads + 1] = url; files[path] = hash end,
      chmod = function() end,
      rename = function(from, to) files[to] = files[from]; files[from] = nil end,
      remove = function(path) removed[#removed + 1] = path; files[path] = nil end,
      nonce = 'test',
    }
  end)

  it('recognizes the supported OS and CPU combinations', function()
    assert.equals('osx-arm64', installer._platform('Darwin', 'arm64'))
    assert.equals('osx-x64', installer._platform('Darwin', 'x86_64'))
    assert.equals('linux-arm64', installer._platform('Linux', 'aarch64'))
    assert.equals('linux-x64', installer._platform('Linux', 'x86_64'))
    assert.equals('win-x64', installer._platform('Windows_NT', 'AMD64'))
    assert.equals('win-arm64', installer._platform('Windows_NT', 'ARM64'))
    assert.is_nil(installer._platform('FreeBSD', 'x86_64'))
    assert.is_nil(installer._platform('Linux', 'i686'))
  end)

  it('downloads the pinned asset, verifies it, and returns its absolute path', function()
    local path, err = installer._install(manifest, ops)
    assert.is_nil(err)
    assert.matches('helper%-v1.0.0/osx%-arm64/', path)
    assert.equals(hash, files[path])
    assert.are.same({ 'https://github.com/csmhowitzer/enhance.nvim/releases/download/helper-v1.0.0/enhance-helper-osx-arm64' }, downloads)
  end)

  it('reuses a verified cache without network access', function()
    local path = assert(installer._install(manifest, ops))
    downloads = {}
    assert.equals(path, installer._install(manifest, ops))
    assert.equals(0, #downloads)
  end)

  it('installs the separately pinned PostgreSQL companion without accepting main-helper substitution', function()
    manifest.helper = 'postgres'
    manifest.artifacts['osx-arm64'].name = 'enhance-helper-postgres-osx-arm64'
    local path, err = installer._install(manifest, ops)
    assert.is_nil(err)
    assert.is_truthy(path:find('enhance-helper-postgres-osx-arm64', 1, true))
    assert.is_truthy(downloads[1]:find('enhance-helper-postgres-osx-arm64', 1, true))
    manifest.artifacts['osx-arm64'].name = 'enhance-helper-osx-arm64'
    assert.is_nil(installer._install(manifest, ops))
  end)

  it('repairs a corrupt cached executable', function()
    local path = assert(installer._install(manifest, ops))
    files[path] = string.rep('b', 64)
    assert.equals(path, installer._install(manifest, ops))
    assert.equals(hash, files[path])
    assert.equals(2, #downloads)
  end)

  it('rejects a checksum mismatch without installing it and releases the lock', function()
    local unlocked = false
    ops.download = function(_, path) files[path] = string.rep('b', 64) end
    ops.unlock = function() unlocked = true end
    local path, err = installer._install(manifest, ops)
    assert.is_nil(path)
    assert.matches('checksum', err)
    assert.equals(1, #removed)
    assert.is_true(unlocked)
    assert.is_nil(next(files))
  end)

  it('preserves earlier releases when a new download fails', function()
    local old = assert(installer._install(manifest, ops))
    manifest.release = 'helper-v1.0.1'
    ops.download = function() error('network unavailable') end
    local path, err = installer._install(manifest, ops)
    assert.is_nil(path)
    assert.matches('network unavailable', err)
    assert.equals(hash, files[old])
  end)

  it('does not download when another installer owns the lock', function()
    ops.lock = function() return false end
    local path, err = installer._install(manifest, ops)
    assert.is_nil(path)
    assert.matches('installation is already running', err)
    assert.equals(0, #downloads)
  end)

  it('rejects an unreleased manifest without network access', function()
    manifest.release = false
    local path, err = installer._install(manifest, ops)
    assert.is_nil(path)
    assert.matches('not published', err)
    assert.equals(0, #downloads)
  end)

  it('rejects unsupported platforms without network access', function()
    ops.platform = 'linux-mips'
    local path, err = installer._install(manifest, ops)
    assert.is_nil(path)
    assert.matches('Unsupported', err)
    assert.equals(0, #downloads)
  end)

  it('rejects malformed checksums and traversal in release or asset names', function()
    for _, change in ipairs({
      function() manifest.artifacts['osx-arm64'].sha256 = 'bad' end,
      function() manifest.artifacts['osx-arm64'].name = '../executable' end,
      function() manifest.release = '../latest' end,
      function() manifest.schema = 2 end,
    }) do
      local saved = vim.deepcopy(manifest)
      change()
      local path, err = installer._install(manifest, ops)
      assert.is_nil(path)
      assert.is_string(err)
      assert.equals(0, #downloads)
      manifest = saved
    end
  end)

  it('does not promote a binary when executable permissions cannot be set', function()
    ops.chmod = function() error('permission denied') end
    local path, err = installer._install(manifest, ops)
    assert.is_nil(path)
    assert.matches('permission denied', err)
    assert.is_nil(next(files))
  end)

  it('hashes binary NUL and newline bytes without text conversion', function()
    local path = vim.fn.tempname()
    local file = assert(io.open(path, 'wb'))
    file:write('a\0b\n')
    file:close()
    local ok, result = pcall(installer._digest, path)
    vim.fn.delete(path)
    assert.is_true(ok, tostring(result))
    assert.equals('3a100994c4e38751871e6e8eef9adad2b20177fdeaf650daacdcd74f4c9421e3', result)
  end)

  it('installs and reuses a binary through actual filesystem operations', function()
    local directory = vim.fn.tempname() .. " helper's cache"
    local ok, err = pcall(function()
      local real = installer._defaults()
      real.root = directory
      real.platform = 'osx-arm64'
      manifest.artifacts['osx-arm64'].sha256 = '3a100994c4e38751871e6e8eef9adad2b20177fdeaf650daacdcd74f4c9421e3'
      local calls = 0
      real.download = function(_, path)
        calls = calls + 1
        local file = assert(io.open(path, 'wb'))
        file:write('a\0b\n')
        file:close()
      end
      local path, error = installer._install(manifest, real)
      assert.is_nil(error)
      assert.equals(manifest.artifacts['osx-arm64'].sha256, installer._digest(path))
      assert.equals(path, installer._install(manifest, real))
      assert.equals(1, calls)
      assert.equals(0, vim.fn.isdirectory(path .. '.lock'))
    end)
    vim.fn.delete(directory, 'rf')
    assert.is_true(ok, tostring(err))
  end)

  it('never downloads while resolving an unpublished release', function()
    local original = installer.manifest
    installer.manifest = function() return { schema = 1, release = false, artifacts = {} } end
    local path, err = installer.path()
    installer.manifest = original
    assert.is_nil(path)
    assert.matches('not published', err)
  end)
end)
