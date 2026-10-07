-- Temporary welcome page and the first, lightweight connected dashboard.
local M = {}
local window_options = {}
local namespace = vim.api.nvim_create_namespace('enhance_landing')
local logo = {
  '███████╗███╗   ██╗██╗  ██╗ █████╗ ███╗   ██╗ ██████╗███████╗',
  '██╔════╝████╗  ██║██║  ██║██╔══██╗████╗  ██║██╔════╝██╔════╝',
  '█████╗  ██╔██╗ ██║███████║███████║██╔██╗ ██║██║     █████╗  ',
  '██╔══╝  ██║╚██╗██║██╔══██║██╔══██║██║╚██╗██║██║     ██╔══╝  ',
  '███████╗██║ ╚████║██║  ██║██║  ██║██║ ╚████║╚██████╗███████╗',
  '╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝',
}

local function fit(text, width)
  text = tostring(text)
  while vim.fn.strdisplaywidth(text) > width do
    text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
  end
  return text .. string.rep(' ', width - vim.fn.strdisplaywidth(text))
end

local function panel(title, body, width)
  local inner = width - 6 -- Border plus two padding cells on each side
  local lines = { '╭' .. string.rep('─', width - 2) .. '╮', '│  ' .. fit(title, inner) .. '  │' }
  lines[#lines + 1] = '│  ' .. string.rep(' ', inner) .. '  │'
  for _, text in ipairs(body) do
    lines[#lines + 1] = '│  ' .. fit(text, inner) .. '  │'
  end
  lines[#lines + 1] = '╰' .. string.rep('─', width - 2) .. '╯'
  return lines
end

local function join_panels(panels, columns)
  local lines = {}
  for start = 1, #panels, columns do
    local count = math.min(columns, #panels - start + 1)
    for row = 1, #panels[start] do
      local parts = {}
      for col = 0, count - 1 do
        parts[#parts + 1] = panels[start + col][row]
      end
      lines[#lines + 1] = table.concat(parts, '  ')
    end
    lines[#lines + 1] = ''
  end
  return lines
end

local function format_count(count)
  return tostring(count):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

local function row_chart(rows, width)
  if rows == nil then return { 'Loading catalog estimates…' } end
  if rows == false then return { 'Table estimates unavailable (check catalog permissions).' } end
  if #rows == 0 then return { 'No table estimates found.' } end

  local body = { 'Top tables by estimated row count' }
  local largest = rows[1].count
  local inner = width - 6
  local name_width = math.min(22, math.max(5, math.floor(inner * 0.3)))
  local count_width = #format_count(largest)
  local bar_width = math.max(1, math.min(40, inner - name_width - count_width - 4))
  for _, row in ipairs(rows) do
    local fill = largest > 0 and math.max(1, math.floor(row.count / largest * bar_width)) or 0
    if row.count == 0 then fill = 0 end
    body[#body + 1] = fit(row.name, name_width) .. '  '
      .. string.rep('█', fill) .. string.rep(' ', bar_width - fill) .. '  ' .. format_count(row.count)
  end
  return body
end

local function activate(win, buf)
  if not window_options[win] then
    window_options[win] = {
      number = vim.wo[win].number,
      relativenumber = vim.wo[win].relativenumber,
      signcolumn = vim.wo[win].signcolumn,
      cursorline = vim.wo[win].cursorline,
      list = vim.wo[win].list,
      wrap = vim.wo[win].wrap,
    }
  end
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].cursorline = false
  vim.wo[win].list = false
  vim.wo[win].wrap = false
  vim.api.nvim_create_autocmd('BufWinLeave', {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if not vim.api.nvim_win_is_valid(win) or M.is_landing(vim.api.nvim_win_get_buf(win)) then
          return
        end
        local original = window_options[win]
        if original then
          for option, value in pairs(original) do
            vim.wo[win][option] = value
          end
          window_options[win] = nil
        end
      end)
    end,
  })
end

local function render(win, subtitle, details, actions, top, heading)
  local previous = vim.api.nvim_win_get_buf(win)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = top and 'hide' or 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'enhance-landing'

  local width = vim.api.nvim_win_get_width(win)
  local banner = top and require('enhance.banner_font').render(heading, width)
    or (width >= 74 and logo or { 'E N H A N C E' })
  local content = vim.deepcopy(banner)
  content[#content + 1] = ''
  local subtitle_index, actions_index
  if top then
    actions_index = #content
    if width >= 80 then
      content[#content + 1] = table.concat(actions, '      ')
    else
      vim.list_extend(content, actions)
    end
    content[#content + 1] = string.rep('─', math.max(0, width - 4))
    content[#content + 1] = ''
    subtitle_index = #content
    content[#content + 1] = subtitle
    content[#content + 1] = ''
    vim.list_extend(content, details)
  else
    subtitle_index = #content
    content[#content + 1] = subtitle
    content[#content + 1] = ''
    content[#content + 1] = string.rep('─', math.min(58, width))
    content[#content + 1] = ''
    vim.list_extend(content, details)
    content[#content + 1] = ''
    actions_index = #content
    content[#content + 1] = 'QUICK ACTIONS'
    vim.list_extend(content, actions)
  end

  local height = vim.api.nvim_win_get_height(win)
  local max_width = 0
  for _, line in ipairs(content) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end
  local padding = top and 2 or math.max(0, math.floor((width - max_width) / 2))
  local lines = {}
  for _ = 1, top and 1 or math.max(0, math.floor((height - #content) / 2)) do
    lines[#lines + 1] = ''
  end
  local first = #lines
  for _, line in ipairs(content) do
    lines[#lines + 1] = string.rep(' ', padding) .. line
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for i = 0, #banner - 1 do
    vim.api.nvim_buf_add_highlight(buf, namespace, 'Title', first + i, padding, -1)
  end
  vim.api.nvim_buf_add_highlight(buf, namespace, 'Comment', first + subtitle_index, padding, -1)
  vim.api.nvim_buf_add_highlight(buf, namespace, 'Title', first + actions_index, padding, -1)
  if top then
    for index, line in ipairs(content) do
      if line:match('^DATABASE OBJECTS') or line:match('^ROWS PER TABLE') then
        vim.api.nvim_buf_add_highlight(buf, namespace, 'Title', first + index - 1, padding, -1)
      end
      local start_col = index > #banner and line:find('█', 1, true)
      if start_col then
        local blocks = line:match('^(.*█+)')
        local end_col = blocks and #blocks or #line
        vim.api.nvim_buf_add_highlight(buf, namespace, 'String', first + index - 1,
          padding + start_col - 1, padding + end_col)
      end
    end
  end
  vim.bo[buf].modifiable = false
  activate(win, buf)
  vim.api.nvim_win_set_buf(win, buf)
  if M.is_landing(previous) then
    vim.api.nvim_buf_delete(previous, { force = true })
  end
  return buf
end

---Whether a buffer belongs to the replaceable Enhance landing page.
---@param buf integer
---@return boolean
function M.is_landing(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == 'enhance-landing'
end

---Return to a dashboard buffer that was hidden while viewing another query.
---@param win integer
---@param buf integer
function M.open_existing(win, buf)
  activate(win, buf)
  vim.api.nvim_win_set_buf(win, buf)
end

---Show the welcome page until a database connection is established.
---@param win integer
---@return integer
function M.show_welcome(win)
  local buf = render(win, 'YOUR DATABASE WORKSPACE', {
    'Welcome! Select a database in the explorer to get started.',
    'A connected overview will appear here once you connect.',
  }, {
    'e   Explore databases',
    'n   New query (after connecting)',
    '?   Help',
  })
  vim.keymap.set('n', 'e', function() require('enhance.explorer').open() end,
    { buffer = buf, desc = 'Focus database explorer' })
  vim.keymap.set('n', 'n', function() require('enhance.explorer').new_query() end,
    { buffer = buf, desc = 'New database query' })
  vim.keymap.set('n', '?', function() vim.cmd('help enhance') end,
    { buffer = buf, desc = 'Enhance help' })
  return buf
end

---Show the connected database overview in cards and metadata panels.
---@param win integer
---@param connection table
---@param tables string[]
---@param view_count integer?
---@param row_counts table[]|false? SQL Server estimated counts, false when unavailable
---@param local_counts table? Saved queries and persisted temp buffers for this connection
---@return integer
function M.show_dashboard(win, connection, tables, view_count, row_counts, local_counts)
  local_counts = local_counts or {}
  local width = math.max(24, vim.api.nvim_win_get_width(win) - 4)
  local columns = width >= 112 and 4 or (width >= 52 and 2 or 1)
  local card_width = math.floor((width - 2 * (columns - 1)) / columns)
  local cards = {
    panel('TABLES', { tostring(#tables) .. ' tables' }, card_width),
    panel('VIEWS', { view_count and tostring(view_count) .. ' views' or 'Not available' }, card_width),
    panel('SAVED QUERIES', { tostring(local_counts.saved_queries or 0) .. ' saved' }, card_width),
    panel('TEMP BUFFERS', { tostring(local_counts.temp_buffers or 0) .. ' on disk' }, card_width),
    panel('ENGINE', { connection.type }, card_width),
    panel('STATUS', { 'Connected' }, card_width),
  }

  local details = join_panels(cards, columns)
  details[#details + 1] = 'DATABASE OBJECTS'
  local names = {}
  for i = 1, math.min(5, #tables) do
    names[#names + 1] = tables[i]
  end
  if #names == 0 then names[1] = 'No tables found' end
  while #names < 5 do names[#names + 1] = '' end
  local database = connection.database or connection.path or connection.name
  local heading = connection.database or (connection.path and vim.fn.fnamemodify(connection.path, ':t'))
    or connection.name
  local host = connection.server or connection.host or 'Local'
  local panel_columns = width >= 58 and 2 or 1
  local panel_width = math.floor((width - 2 * (panel_columns - 1)) / panel_columns)
  local panels = {
    panel('TABLES  ·  first 5', names, panel_width),
    panel('CONNECTION', { 'Database: ' .. database, 'Server:   ' .. host,
      'Engine:   ' .. connection.type, '', '' }, panel_width),
  }
  vim.list_extend(details, join_panels(panels, panel_columns))
  local db_type = connection.type:lower():gsub('[%s%-_]', '')
  if db_type == 'sqlserver' or db_type == 'mssql' then
    details[#details + 1] = 'ROWS PER TABLE'
    vim.list_extend(details, panel('ESTIMATED ROWS  ·  TOP 8', row_chart(row_counts, width), width))
  end
  local buf = render(win, connection.name .. '  |  DASHBOARD', details, {
    'n   New query',
    'e   Explore databases',
    'r   Refresh',
    '?   Help',
  }, true, heading)
  vim.keymap.set('n', 'n', function() require('enhance.explorer').new_query() end,
    { buffer = buf, desc = 'New database query' })
  vim.keymap.set('n', 'e', function() require('enhance.explorer').open() end,
    { buffer = buf, desc = 'Focus database explorer' })
  vim.keymap.set('n', 'r', function() require('enhance.explorer').refresh_dashboard(connection) end,
    { buffer = buf, desc = 'Refresh database dashboard' })
  vim.keymap.set('n', '?', function() vim.cmd('help enhance') end,
    { buffer = buf, desc = 'Enhance help' })
  return buf
end

M._panel = panel

return M
