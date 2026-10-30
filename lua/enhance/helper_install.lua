-- Release installation only. Query execution must never download executables.
local M = {}
local uv = vim.uv or vim.loop
local source = debug.getinfo(1, 'S').source:sub(2)
local plugin_root = vim.fn.fnamemodify(source, ':h:h:h')
local release_base = 'https://github.com/csmhowitzer/enhance.nvim/releases/download/'

---@class EnhanceHelperArtifact
---@field name string Release asset filename (single-file executable)
---@field sha256 string Lowercase SHA-256 pinned in the plugin checkout
---@class EnhanceHelperRelease
---@field schema integer Manifest format version
---@field release string|false Immutable helper release tag, or false before first release
---@field artifacts table<string, EnhanceHelperArtifact> Runtime identifier to asset
---@class EnhanceHelperInstallOps
---@field platform string?
---@field root string Absolute cache directory
---@field nonce string Unique staging filename suffix
---@field exists fun(path: string): boolean
---@field fingerprint fun(path: string): string? size/mtime/inode, nil when the file is missing
---@field digest fun(path: string): string
---@field mkdir fun(path: string)
---@field lock fun(path: string): boolean
---@field unlock fun(path: string)
---@field remove fun(path: string)
---@field chmod fun(path: string)
---@field rename fun(from: string, to: string)
---@field download fun(url: string, path: string)

---Return the runtime identifier, or nil for unsupported platforms.
---@param system string
---@param machine string
---@return string?
local function platform(system, machine)
  local os = ({ Darwin = 'osx', Linux = 'linux', Windows_NT = 'win' })[system]
  local arch = ({ x86_64 = 'x64', amd64 = 'x64', arm64 = 'arm64', aarch64 = 'arm64' })[machine:lower()]
  if os and arch then return os .. '-' .. arch end
end

---Run an argument-array command without a shell; return its stdout.
---@param argv string[]
---@return string
local function run(argv)
  local result = vim.system(argv, { text = true }):wait(180000)
  if result.code ~= 0 then error('Helper packaging command failed: ' .. (result.stderr or ''), 0) end
  return result.stdout or ''
end

---Hash binary files with OS utilities, never Vim string hashing (binary NULs).
---@param path string
---@return string
local function digest(path)
  local output
  if vim.fn.executable('sha256sum') == 1 then
    output = run({ 'sha256sum', '--', path })
  elseif vim.fn.executable('shasum') == 1 then
    output = run({ 'shasum', '-a', '256', '--', path })
  elseif vim.fn.has('win32') == 1 then
    local shell = vim.fn.executable('pwsh') == 1 and 'pwsh' or 'powershell.exe'
    output = run({ shell, '-NoProfile', '-NonInteractive', '-Command',
      "(Get-FileHash -Algorithm SHA256 -LiteralPath '" .. path:gsub("'", "''") .. "').Hash" })
  else
    error('Helper verification requires sha256sum or shasum', 0)
  end
  local hash = output:match('^%s*(%x+)')
  if not hash or #hash ~= 64 then error('Invalid SHA-256 output', 0) end
  return hash:lower()
end

---Load the manifest shipped with this exact plugin checkout, not remote latest.
---@return EnhanceHelperRelease
function M.manifest(db)
  local file = (db == 'postgres' or db == 'postgresql') and 'helper-postgres-release.json' or 'helper-release.json'
  return vim.json.decode(table.concat(vim.fn.readfile(plugin_root .. '/' .. file), '\n'))
end

---@return EnhanceHelperInstallOps
local function defaults()
  local uname = uv.os_uname()
  local rid = platform(uname.sysname, uname.machine)
  -- glibc and musl are distinct runtime targets. Do not install glibc on Alpine.
  if uname.sysname == 'Linux' and uv.fs_stat('/etc/alpine-release') then rid = nil end
  return {
    platform = rid, root = vim.fn.stdpath('data') .. '/enhance/helper',
    nonce = tostring(uv.os_getpid()) .. '-' .. tostring(uv.hrtime()),
    exists = function(path) return uv.fs_stat(path) ~= nil end,
    -- size, mtime and inode: a verified helper is hashed again only when one of these changes
    fingerprint = function(path)
      local stat = uv.fs_stat(path)
      return stat and table.concat({ stat.size, stat.mtime.sec, stat.mtime.nsec, stat.ino }, ':') or nil
    end,
    digest = digest,
    mkdir = function(path) vim.fn.mkdir(path, 'p', 448) end,
    lock = function(path) return uv.fs_mkdir(path, 448) ~= nil end,
    unlock = function(path) uv.fs_rmdir(path) end,
    remove = function(path) uv.fs_unlink(path) end,
    chmod = function(path)
      if uname.sysname ~= 'Windows_NT' then assert(uv.fs_chmod(path, 448)) end
    end,
    rename = function(from, to) assert(uv.fs_rename(from, to)) end,
    download = function(url, path)
      if vim.fn.executable('curl') ~= 1 then error('Helper installation requires curl', 0) end
      run({ 'curl', '--fail', '--silent', '--show-error', '--location',
        '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '15',
        '--max-time', '150', '--max-filesize', '209715200', '--output', path, url })
    end,
  }
end

---@param manifest EnhanceHelperRelease
---@param rid string?
---@return EnhanceHelperArtifact?
---@return string? error
local function validate(manifest, rid)
  if type(manifest) ~= 'table' or manifest.schema ~= 1 then return nil, 'Invalid helper manifest schema' end
  if manifest.helper ~= nil and manifest.helper ~= 'postgres' then return nil, 'Invalid helper family' end
  if manifest.release == false then return nil, 'Helper release is not published yet' end
  if type(manifest.release) ~= 'string' or not manifest.release:match('^helper%-v%d+%.%d+%.%d+$') then
    return nil, 'Invalid pinned helper release tag'
  end
  local supported = { ['osx-x64'] = true, ['osx-arm64'] = true, ['linux-x64'] = true,
    ['linux-arm64'] = true, ['win-x64'] = true, ['win-arm64'] = true }
  if not rid or not supported[rid] then return nil, 'Unsupported helper platform' end
  local artifact = type(manifest.artifacts) == 'table' and manifest.artifacts[rid]
  if type(artifact) ~= 'table' then return nil, 'Unsupported helper platform: ' .. rid end
  local prefix = manifest.helper == 'postgres' and 'enhance-helper-postgres-' or 'enhance-helper-'
  local expected = prefix .. rid .. (rid:match('^win%-') and '.exe' or '')
  if artifact.name ~= expected then return nil, 'Invalid helper asset name' end
  if type(artifact.sha256) ~= 'string' or #artifact.sha256 ~= 64 or artifact.sha256:find('[^0-9a-f]') then
    return nil, 'Invalid pinned helper checksum'
  end
  return artifact
end

---Install a pinned executable transactionally. Dependencies are injectable for tests.
---@param manifest EnhanceHelperRelease
---@param ops EnhanceHelperInstallOps Filesystem, platform, hashing, and network operations
---@return string? path
---@return string? error
local function install(manifest, ops)
  local artifact, err = validate(manifest, ops.platform)
  if not artifact then return nil, err end
  local directory = ops.root .. '/' .. manifest.release .. '/' .. ops.platform
  local target = directory .. '/' .. artifact.sha256 .. '-' .. artifact.name
  if ops.exists(target) and ops.digest(target) == artifact.sha256 then return target end
  ops.mkdir(directory)
  local lock = target .. '.lock'
  if not ops.lock(lock) then return nil, 'Helper installation is already running: ' .. lock end
  local temporary = target .. '.download-' .. ops.nonce
  local ok, result = pcall(function()
    -- Recheck after obtaining ownership; never execute the staging download.
    if ops.exists(target) and ops.digest(target) == artifact.sha256 then return target end
    ops.download(release_base .. manifest.release .. '/' .. artifact.name, temporary)
    if ops.digest(temporary) ~= artifact.sha256 then error('Helper checksum mismatch', 0) end
    ops.chmod(temporary)
    ops.rename(temporary, target)
    return target
  end)
  ops.remove(temporary)
  ops.unlock(lock)
  if not ok then return nil, tostring(result) end
  return result
end

---Explicit install/update entry point, used by lazy.nvim's automatic build.lua.
---@return string? path
---@return string? error
function M.install()
  local ok, path, err = pcall(function()
    local main_path, main_error = install(M.manifest(), defaults())
    if not main_path then return nil, main_error end
    local postgres = M.manifest('postgresql')
    if postgres.release ~= false then
      local postgres_path, postgres_error = install(postgres, defaults())
      if not postgres_path then return nil, postgres_error end
    end
    return main_path
  end)
  if not ok then return nil, tostring(path) end
  return path, err
end

---Helpers whose checksum matched this session: path -> fingerprint of the file at that time
---@type table<string, string>
local verified = {}

---Resolve a verified cached helper. Hashing a 77 MB helper blocks for ~100 ms, so it's done once per
---session per file; the file is hashed again whenever its size, mtime or inode changes.
---@param manifest EnhanceHelperRelease
---@param ops EnhanceHelperInstallOps
---@param cache table<string, string> verified paths and their fingerprints
---@return string? path
---@return string? error
local function resolve(manifest, ops, cache)
  local artifact, validation_error = validate(manifest, ops.platform)
  if not artifact then return nil, validation_error end
  local target = ops.root .. '/' .. manifest.release .. '/' .. ops.platform .. '/' .. artifact.sha256 .. '-' .. artifact.name
  local fingerprint = ops.fingerprint(target)
  if not fingerprint then
    cache[target] = nil
    return nil, 'Helper is missing; rebuild enhance.nvim in lazy.nvim'
  end
  if cache[target] == fingerprint then return target end
  if ops.digest(target) ~= artifact.sha256 then
    cache[target] = nil
    return nil, 'Helper checksum mismatch; rebuild enhance.nvim in lazy.nvim'
  end
  cache[target] = fingerprint
  return target
end

---Resolve a verified cached helper, without downloading or changing files.
---@return string? path
---@return string? error
function M.path(db)
  local ok, path, err = pcall(function()
    return resolve(M.manifest(db), defaults(), verified)
  end)
  if not ok then return nil, tostring(path) end
  return path, err
end

M._platform = platform
M._install = install
M._resolve = resolve
M._digest = digest
M._defaults = defaults
return M
