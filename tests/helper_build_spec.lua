describe('automatic lazy.nvim helper build hook', function()
  local build = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h') .. '/build.lua'
  local original_dofile, original_notify, installer, calls

  before_each(function()
    original_dofile, original_notify = dofile, vim.notify
    calls = 0
    installer = {
      manifest = function() return { release = 'helper-v1.0.0' } end,
      install = function() calls = calls + 1; return '/cache/helper' end,
    }
    _G.dofile = function(path)
      if path:match('/lua/enhance/helper_install.lua$') then return installer end
      return original_dofile(path)
    end
    vim.notify = function() end
  end)

  after_each(function()
    _G.dofile, vim.notify = original_dofile, original_notify
  end)

  it('installs without requiring runtimepath or a user-specified build command', function()
    original_dofile(build)
    assert.equals(1, calls)
  end)

  it('surfaces installation failure rather than reporting success', function()
    installer.install = function() return nil, 'checksum mismatch' end
    local ok, err = pcall(original_dofile, build)
    assert.is_false(ok)
    assert.matches('checksum mismatch', err)
  end)

  it('does not download development artifacts before the first release', function()
    installer.manifest = function() return { release = false } end
    original_dofile(build)
    assert.equals(0, calls)
  end)
end)
