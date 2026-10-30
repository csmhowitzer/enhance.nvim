-- Tests must never touch the user's real Neovim data (query files, pins, connection folders).
describe('test isolation', function()
  it('runs with data, cache and state in a temporary test home', function()
    local home = vim.env.ENHANCE_TEST_HOME
    assert.is_truthy(home and home ~= '', 'tests/minimal_init.lua sets ENHANCE_TEST_HOME')
    for _, what in ipairs({ 'data', 'cache', 'state' }) do
      local dir = vim.fn.stdpath(what)
      assert.equals(home, dir:sub(1, #home), what .. ' dir must be inside the test home, got ' .. dir)
    end
  end)
end)
