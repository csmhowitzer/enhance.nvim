describe('enhance splash and dashboard font', function()
  local font = require('enhance.banner_font')

  it('spells database names from letters, numbers, and separators', function()
    local banner = font.render('Ab_12.db', 80)
    assert.equals(6, #banner)
    assert.same(banner, font.render('AB_12.DB', 80))
    assert.is_false(vim.deep_equal(banner, font.render('ZZ_12.DB', 80)))
    assert.is_not_nil(table.concat(banner, '\n'):find('█', 1, true))
  end)

  it('renders the original ENHANCE splash lettering', function()
    assert.same({
      '███████╗███╗   ██╗██╗  ██╗ █████╗ ███╗   ██╗ ██████╗███████╗',
      '██╔════╝████╗  ██║██║  ██║██╔══██╗████╗  ██║██╔════╝██╔════╝',
      '█████╗  ██╔██╗ ██║███████║███████║██╔██╗ ██║██║     █████╗  ',
      '██╔══╝  ██║╚██╗██║██╔══██║██╔══██║██║╚██╗██║██║     ██╔══╝  ',
      '███████╗██║ ╚████║██║  ██║██║  ██║██║ ╚████║╚██████╗███████╗',
      '╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝',
    }, font.render('ENHANCE', 80))
  end)

  it('wraps a long name without exceeding the pane width', function()
    local banner = font.render('example_sqlserver', 42)
    assert.is_true(#banner > 5)
    for _, line in ipairs(banner) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= 40)
    end
  end)

  it('wraps variable-width glyphs without splitting letters', function()
    local banner = font.render('MMMM-001.db', 24)
    assert.is_true(#banner > 6)
    for _, line in ipairs(banner) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= 22)
    end
  end)
end)
