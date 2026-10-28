-- Tests for the global key prefix (keymaps.prefix, default <leader>o)

describe("enhance keymaps.prefix", function()
  local enhance
  local suffixes = { "e", "q", "r", "j", "h", "x", "d" }

  local function mapped(lhs)
    return vim.fn.maparg(lhs, "n") ~= ""
  end

  local function clear(prefix)
    for _, s in ipairs(suffixes) do
      pcall(vim.keymap.del, "n", prefix .. s)
    end
  end

  before_each(function()
    vim.g.mapleader = " "
    package.loaded["enhance"] = nil
    package.loaded["enhance.init"] = nil
    package.loaded["enhance.connections"] = nil
    enhance = require("enhance")
    clear("<leader>o")
    clear("<leader>d")
    clear("<leader>z")
  end)

  local function setup(keymaps)
    enhance.setup({ connections_file = {}, keymaps = keymaps })
  end

  it("maps the global keys under <leader>o by default", function()
    setup(nil)
    for _, s in ipairs(suffixes) do
      assert.is_true(mapped("<leader>o" .. s), "<leader>o" .. s)
      assert.is_false(mapped("<leader>d" .. s), "<leader>d" .. s)
    end
  end)

  it("keeps the old <leader>d keys when asked", function()
    setup({ prefix = "<leader>d" })
    assert.is_true(mapped("<leader>de"))
    assert.is_true(mapped("<leader>dd"))
    assert.equals("<leader>dp", enhance.prefixed("p"))
  end)

  it("maps nothing when the prefix is false", function()
    setup({ prefix = false })
    assert.is_nil(enhance.prefixed("e"))
    for _, s in ipairs(suffixes) do
      assert.is_false(mapped("<leader>o" .. s))
    end
  end)

  it("rejects a prefix that isn't a string or false", function()
    assert.has_error(function()
      enhance.setup({ keymaps = { prefix = 1 } })
    end)
  end)
end)
