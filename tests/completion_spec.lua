describe('enhance.completion', function()
  local completion = require('enhance.completion')

  it('builds a Dadbod URL for the selected SQL Server database', function()
    assert.equals(
      'sqlserver://db.example:1433/Example%20DB;user=reader%40work;password=p%40ss%3Bword;TrustServerCertificate=true',
      completion.sqlserver_url({
        type = 'sqlserver', server = 'db.example,1433', database = 'Example DB',
        user = 'reader@work', password = 'p@ss;word',
      })
    )
    assert.equals('sqlserver://db.example/sample;user=reader', completion.sqlserver_url({
      type = 'mssql', host = 'db.example', database = 'sample', user = 'reader',
      trust_server_certificate = false,
    }))
    assert.is_nil(completion.sqlserver_url({ type = 'sqlite', path = '/tmp/sample.db' }))
  end)

  it('sets completion only in SQL Server query buffers', function()
    local sql = vim.api.nvim_create_buf(false, true)
    local other_sql = vim.api.nvim_create_buf(false, true)
    local sqlite = vim.api.nvim_create_buf(false, true)
    vim.bo[sql].filetype = 'sql'
    vim.bo[other_sql].filetype = 'sql'
    vim.bo[sqlite].filetype = 'sql'

    completion.setup(sql, {
      type = 'sqlserver', server = 'localhost', database = 'sample',
      user = 'reader', password = 'secret',
    })
    completion.setup(other_sql, {
      type = 'sqlserver', host = 'other.example', database = 'other_db',
    })
    completion.setup(sqlite, { type = 'sqlite', path = '/tmp/sample.db' })

    assert.equals('sqlserver://localhost/sample;user=reader;password=secret;TrustServerCertificate=true', vim.b[sql].db)
    assert.equals('sqlserver://other.example/other_db;TrustServerCertificate=true', vim.b[other_sql].db)
    assert.equals('vim_dadbod_completion#omni', vim.bo[sql].omnifunc)
    assert.is_nil(vim.b[sqlite].db)
    assert.not_equals('vim_dadbod_completion#omni', vim.bo[sqlite].omnifunc)
    vim.api.nvim_buf_delete(sql, { force = true })
    vim.api.nvim_buf_delete(other_sql, { force = true })
    vim.api.nvim_buf_delete(sqlite, { force = true })
  end)
end)
