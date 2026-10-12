describe('SQL Server helper protocol', function()
  it('passes the actual .NET protocol and reader-mapping regression suite', function()
    local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    local sdk = vim.env.ENHANCE_TEST_DOTNET10
    local project = root .. '/helper-tests/enhance-helper-tests.csproj'
    local command = { sdk or 'dotnet', 'run', '--project', project, '--verbosity', 'quiet' }
    if sdk then
      -- Apply the release target to both projects, including project references.
      local restored = vim.fn.system({ sdk, 'restore', project, '-p:EnhanceReleaseTargetFramework=net10.0', '--verbosity', 'quiet' })
      assert.equals(0, vim.v.shell_error, restored)
      vim.list_extend(command, { '--no-restore', '--framework', 'net10.0', '-p:EnhanceReleaseTargetFramework=net10.0' })
    end
    local output = vim.fn.system(command)
    local code = vim.v.shell_error
    assert.equals(0, code, output)
    local report = vim.json.decode(output:match('(\n?%[.*%])%s*$'))
    assert.equals(14, #report)
    for _, test in ipairs(report) do assert.is_true(test.ok, test.name .. ': ' .. test.error) end
  end)

  local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
  local executable = root .. '/dist/helper-publish/osx-arm64/enhance-helper'
  if vim.fn.executable(executable) == 1 then
    it('runs the published single-file helper handshake without dotnet', function()
      local output = vim.fn.system({ executable, '--version' })
      assert.equals(0, vim.v.shell_error, output)
      local response = vim.json.decode(output)
      assert.equals(1, response.protocol)
      assert.equals('1.0.0', response.helperVersion)
    end)

    it('rejects malformed stdin in the published helper without leaking its contents', function()
      local output = vim.fn.system({ executable }, '{secret-password')
      assert.equals(1, vim.v.shell_error, output)
      local response = vim.json.decode(output)
      assert.is_false(response.ok)
      assert.equals('invalid_request', response.errors[1].kind)
      assert.is_nil(output:find('secret-password', 1, true))
    end)
  end
end)
