-- No routine notifications: only warnings and errors, plus the two toggles whose state isn't visible
describe('notifications', function()
  it('are INFO only for the enabled and result-formatting toggles', function()
    local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h') .. '/lua/enhance'
    local allowed = { ['init.lua'] = 1, ['config.lua'] = 1 }
    local found = {}
    for _, file in ipairs(vim.fn.globpath(root, '**/*.lua', false, true)) do
      local n = select(2, table.concat(vim.fn.readfile(file), '\n'):gsub('vim%.log%.levels%.INFO', ''))
      local name = vim.fn.fnamemodify(file, ':t')
      if n > (allowed[name] or 0) then found[#found + 1] = name .. ': ' .. n end
    end
    assert.same({}, found, 'routine INFO notifications are back')
  end)
end)
