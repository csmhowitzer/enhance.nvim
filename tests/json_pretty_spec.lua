-- JSON pretty-printing: pure Lua, faithful to the original text, jq's layout
describe('json_utils.pretty_print_string', function()
  local json = require('enhance.json_utils')

  it('indents like jq and keeps key order', function()
    assert.equals(table.concat({
      '{',
      '  "zeta": 1,',
      '  "alpha": [',
      '    true,',
      '    null,',
      '    {',
      '      "b": "x"',
      '    }',
      '  ]',
      '}',
    }, '\n'), json.pretty_print_string('{"zeta":1,"alpha":[true,null,{"b":"x"}]}'))
  end)

  it('copies strings, escapes and number formats exactly', function()
    local out = json.pretty_print_string('{"s":"a, {b}: [c] \\"q\\" \\\\","n":1.50,"e":1e10,"neg":-0.0}')
    assert.truthy(out:find('"s": "a, {b}: [c] \\"q\\" \\\\"', 1, true))
    assert.truthy(out:find('"n": 1.50', 1, true))
    assert.truthy(out:find('"e": 1e10', 1, true))
    assert.truthy(out:find('"neg": -0.0', 1, true))
  end)

  it('keeps empty objects and arrays on one line, and unicode as is', function()
    assert.equals('{\n  "o": {},\n  "a": [],\n  "u": "café ☕"\n}',
      json.pretty_print_string('{ "o" : { } , "a":[ ], "u":"café ☕" }'))
    assert.equals('[]', json.pretty_print_string('[]'))
  end)

  it('returns invalid JSON unchanged', function()
    assert.equals('{"a":', json.pretty_print_string('{"a":'))
    assert.equals('not json', json.pretty_print_string('not json'))
  end)

  it('starts no process', function()
    local old_system, old_vsystem, spawned = vim.fn.system, vim.system, false
    vim.fn.system = function() spawned = true; return '' end
    vim.system = function() spawned = true end
    json.pretty_print_string('{"a":[1,2,{"b":3}]}')
    vim.fn.system, vim.system = old_system, old_vsystem
    assert.is_false(spawned)
  end)
end)
