-- Six-row ANSI Shadow alphabet shared by the splash and dashboard headers.
local M = {}

-- Rows are separated by '/'; padding to each glyph's widest row preserves the
-- spacing of the original ENHANCE splash logo.
local glyphs = {
  A = ' █████╗ /██╔══██╗/███████║/██╔══██║/██║  ██║/╚═╝  ╚═╝',
  B = '██████╗ /██╔══██╗/██████╔╝/██╔══██╗/██████╔╝/╚═════╝ ',
  C = ' ██████╗/██╔════╝/██║     /██║     /╚██████╗/ ╚═════╝',
  D = '██████╗ /██╔══██╗/██║  ██║/██║  ██║/██████╔╝/╚═════╝ ',
  E = '███████╗/██╔════╝/█████╗  /██╔══╝  /███████╗/╚══════╝',
  F = '███████╗/██╔════╝/█████╗  /██╔══╝  /██║     /╚═╝     ',
  G = ' ██████╗ /██╔════╝ /██║  ███╗/██║   ██║/╚██████╔╝/ ╚═════╝ ',
  H = '██╗  ██╗/██║  ██║/███████║/██╔══██║/██║  ██║/╚═╝  ╚═╝',
  I = '██╗/██║/██║/██║/██║/╚═╝',
  J = '     ██╗/     ██║/     ██║/██   ██║/╚█████╔╝/ ╚════╝ ',
  K = '██╗  ██╗/██║ ██╔╝/█████╔╝ /██╔═██╗ /██║  ██╗/╚═╝  ╚═╝',
  L = '██╗     /██║     /██║     /██║     /███████╗/╚══════╝',
  M = '███╗   ███╗/████╗ ████║/██╔████╔██║/██║╚██╔╝██║/██║ ╚═╝ ██║/╚═╝     ╚═╝',
  N = '███╗   ██╗/████╗  ██║/██╔██╗ ██║/██║╚██╗██║/██║ ╚████║/╚═╝  ╚═══╝',
  O = ' ██████╗ /██╔═══██╗/██║   ██║/██║   ██║/╚██████╔╝/ ╚═════╝ ',
  P = '██████╗ /██╔══██╗/██████╔╝/██╔═══╝ /██║     /╚═╝     ',
  Q = ' ██████╗ /██╔═══██╗/██║   ██║/██║▄▄ ██║/╚██████╔╝/ ╚══▀▀═╝',
  R = '██████╗ /██╔══██╗/██████╔╝/██╔══██╗/██║  ██║/╚═╝  ╚═╝',
  S = '███████╗/██╔════╝/███████╗/╚════██║/███████║/╚══════╝',
  T = '████████╗/╚══██╔══╝/   ██║   /   ██║   /   ██║   /   ╚═╝   ',
  U = '██╗   ██╗/██║   ██║/██║   ██║/██║   ██║/╚██████╔╝/ ╚═════╝ ',
  V = '██╗   ██╗/██║   ██║/██║   ██║/╚██╗ ██╔╝/ ╚████╔╝ /  ╚═══╝  ',
  W = '██╗    ██╗/██║    ██║/██║ █╗ ██║/██║███╗██║/╚███╔███╔╝/ ╚══╝╚══╝ ',
  X = '██╗  ██╗/╚██╗██╔╝/ ╚███╔╝ / ██╔██╗ /██╔╝ ██╗/╚═╝  ╚═╝',
  Y = '██╗   ██╗/╚██╗ ██╔╝/ ╚████╔╝ /  ╚██╔╝  /   ██║   /   ╚═╝   ',
  Z = '███████╗/╚══███╔╝/  ███╔╝ / ███╔╝  /███████╗/╚══════╝',
  ['0'] = ' ██████╗ /██╔═████╗/██║██╔██║/████╔╝██║/╚██████╔╝/ ╚═════╝ ',
  ['1'] = ' ██╗/███║/╚██║/ ██║/ ██║/ ╚═╝',
  ['2'] = '██████╗ /╚════██╗/ █████╔╝/██╔═══╝ /███████╗/╚══════╝',
  ['3'] = '██████╗ /╚════██╗/ █████╔╝/ ╚═══██╗/██████╔╝/╚═════╝ ',
  ['4'] = '██╗  ██╗/██║  ██║/███████║/╚════██║/     ██║/     ╚═╝',
  ['5'] = '███████╗/██╔════╝/███████╗/╚════██║/███████║/╚══════╝',
  ['6'] = ' ██████╗ /██╔════╝ /███████╗ /██╔═══██╗/╚██████╔╝/ ╚═════╝ ',
  ['7'] = '███████╗/╚════██║/    ██╔╝/   ██╔╝ /   ██║  /   ╚═╝  ',
  ['8'] = ' █████╗ /██╔══██╗/╚█████╔╝/██╔══██╗/╚█████╔╝/ ╚════╝ ',
  ['9'] = ' █████╗ /██╔══██╗/╚██████║/ ╚═══██║/ █████╔╝/ ╚════╝ ',
  ['_'] = '        /        /        /        /███████╗/╚══════╝',
  ['.'] = '   /   /   /   /██╗/╚═╝',
  ['-'] = '      /      /█████╗/╚════╝/      /      ',
  ['/'] = '    ██╗/   ██╔╝/  ██╔╝ / ██╔╝  /██╔╝   /╚═╝    ',
  [' '] = '  /  /  /  /  /  ',
  ['?'] = '██████╗ /╚════██╗/  ▄███╔╝/  ▀▀══╝ /  ██╗   /  ╚═╝   ',
}

local prepared = {}
for char, glyph in pairs(glyphs) do
  local rows = vim.split(glyph, '/', { plain = true })
  local width = 0
  for _, row in ipairs(rows) do width = math.max(width, vim.fn.strdisplaywidth(row)) end
  for i, row in ipairs(rows) do
    rows[i] = row .. string.rep(' ', width - vim.fn.strdisplaywidth(row))
  end
  prepared[char] = { rows = rows, width = width }
end

---Spell a name in the splash font, wrapping at glyph boundaries.
---@param name string
---@param width integer Available display cells (including the left margin)
---@return string[] banner
function M.render(name, width)
  local banner, chunk, used = {}, {}, 0
  local available = math.max(1, width - 2)
  local function append_chunk()
    if #chunk == 0 then return end
    for row = 1, 6 do
      local parts = {}
      for _, glyph in ipairs(chunk) do parts[#parts + 1] = glyph.rows[row] end
      banner[#banner + 1] = table.concat(parts)
    end
    chunk, used = {}, 0
  end
  name = tostring(name):upper()
  for i = 0, vim.fn.strchars(name) - 1 do
    local glyph = prepared[vim.fn.strcharpart(name, i, 1)] or prepared['?']
    if used + glyph.width > available and #chunk > 0 then
      append_chunk()
      banner[#banner + 1] = ''
    end
    chunk[#chunk + 1] = glyph
    used = used + glyph.width
  end
  append_chunk()
  return banner
end

return M
