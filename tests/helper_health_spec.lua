describe('helper packaging diagnostics', function()
  local old_helper, old_health, reports
  before_each(function()
    old_helper, old_health = package.loaded['enhance.helper_install'], vim.health
    reports = {}
    vim.health = {}
    for _, level in ipairs({ 'ok', 'info', 'warn' }) do
      vim.health[level] = function(message) reports[#reports + 1] = { level, message } end
    end
    package.loaded['enhance.helper_install'] = {
      path = function() return '/cache/helper' end,
      install = function() error('health checks must never install or download') end,
    }
  end)

  after_each(function()
    package.loaded['enhance.helper_install'], vim.health = old_helper, old_health
  end)

  it('reports the verified helper cache path', function()
    require('enhance.health')._check_helper()
    assert.equals('ok', reports[1][1])
    assert.matches('/cache/helper', reports[1][2])
  end)

  it('warns that an unpublished release blocks SQL Server queries', function()
    package.loaded['enhance.helper_install'].path = function() return nil, 'Helper release is not published yet' end
    require('enhance.health')._check_helper()
    assert.equals('warn', reports[1][1])
    assert.matches('not published', reports[1][2])
    assert.matches('SQL Server queries unavailable', reports[1][2])
  end)

  it('reports a corrupt or missing helper without downloading', function()
    package.loaded['enhance.helper_install'].path = function() return nil, 'Helper checksum mismatch; rebuild enhance.nvim in lazy.nvim' end
    require('enhance.health')._check_helper()
    assert.equals('warn', reports[1][1])
    assert.matches('checksum mismatch', reports[1][2])
  end)

  it('looks up the PostgreSQL companion independently without network access', function()
    local selected
    package.loaded['enhance.helper_install'].path = function(db) selected = db; return '/cache/postgres' end
    require('enhance.health')._check_helper('postgresql')
    assert.equals('postgresql', selected)
    assert.matches('PostgreSQL', reports[1][2])
  end)
end)
