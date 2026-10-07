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

---Center a card action in its top border when there is room.
local function hinted_panel(title, body, width, hint)
  local lines = panel(title, body, width)
  if width >= #hint + 4 then
    local sides = width - 2 - #hint - 2
    local left = math.floor(sides / 2)
    lines[1] = '╭' .. string.rep('─', left) .. ' ' .. hint .. ' '
      .. string.rep('─', sides - left) .. '╮'
  end
  return lines
end

local function reference_panel(body, width)
  local lines = hinted_panel('', body, width, '<CR> to select')
  table.remove(lines, 2) -- Only the section heading names the card.
  return lines
end

-- Keep reference icons consistent with the corresponding explorer nodes.
local reference_icons = {
  View = '󰒉', Procedure = '󰊢', Function = '󰡱', ['Saved Query'] = '',
}

local sql_keywords = {
  CREATE = true, TABLE = true, PRIMARY = true, KEY = true, FOREIGN = true,
  NOT = true, NULL = true, DEFAULT = true, IDENTITY = true, AS = true,
  CONSTRAINT = true, UNIQUE = true, REFERENCES = true, CHECK = true,
  COLLATE = true, PERSISTED = true, ON = true,
}
local sql_types = {
  BIGINT = true, BINARY = true, BIT = true, CHAR = true, DATE = true,
  DATETIME = true, DATETIME2 = true, DATETIMEOFFSET = true, DECIMAL = true,
  FLOAT = true, INT = true, MONEY = true, NCHAR = true, NUMERIC = true,
  NVARCHAR = true, REAL = true, SMALLINT = true, SMALLMONEY = true,
  TIME = true, TINYINT = true, UNIQUEIDENTIFIER = true, VARBINARY = true,
  VARCHAR = true, XML = true, MAX = true,
}

---Highlight SQL tokens only within a CREATE TABLE card's script lines.
local function highlight_sql_line(buf, line_number, text, column)
  local function mark(first, last, group)
    vim.api.nvim_buf_add_highlight(buf, namespace, group, line_number, column + first - 1, column + last)
  end
  local pos = 1
  while pos <= #text do
    local char = text:sub(pos, pos)
    if text:sub(pos, pos + 1) == '--' then
      mark(pos, #text, 'Comment')
      break
    elseif char == '[' then
      local last = pos + 1
      while last <= #text do
        if text:sub(last, last) == ']' then
          if text:sub(last + 1, last + 1) ~= ']' then break end
          last = last + 1
        end
        last = last + 1
      end
      last = math.min(last, #text)
      mark(pos, last, 'Identifier')
      pos = last + 1
    elseif char == "'" then
      local last = pos + 1
      while last <= #text do
        if text:sub(last, last) == "'" then
          if text:sub(last + 1, last + 1) ~= "'" then break end
          last = last + 1
        end
        last = last + 1
      end
      last = math.min(last, #text)
      mark(pos, last, 'String')
      pos = last + 1
    elseif char:match('%d') then
      local number = text:sub(pos):match('^%d+%.?%d*')
      mark(pos, pos + #number - 1, 'Number')
      pos = pos + #number
    elseif char:match('[%a_]') then
      local word = text:sub(pos):match('^[%a_][%w_]*')
      local upper = word:upper()
      if sql_keywords[upper] then mark(pos, pos + #word - 1, 'Statement') end
      if sql_types[upper] then mark(pos, pos + #word - 1, 'Type') end
      pos = pos + #word
    else
      pos = pos + 1
    end
  end
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

local function bar_rows(rows, width, heading)
  local body = { heading }
  local largest = 0
  for _, row in ipairs(rows) do largest = math.max(largest, row.count or 0) end
  local inner = width - 6
  local count_width = math.max(3, #format_count(largest))
  local name_width = math.max(5, math.min(22, math.floor(inner * 0.42), inner - count_width - 5))
  local bar_width = math.max(1, math.min(40, inner - name_width - count_width - 4))
  for i, row in ipairs(rows) do
    local fill = row.count and row.count > 0 and largest > 0
      and math.max(1, math.floor(row.count / largest * bar_width)) or 0
    local count = row.count and format_count(row.count) or 'N/A'
    body[#body + 1] = fit(row.name, name_width) .. '  '
      .. string.rep('█', fill) .. string.rep(' ', bar_width - fill) .. '  ' .. count
    if i < #rows then body[#body + 1] = '' end
  end
  return body
end

local function row_chart(rows, width)
  if rows == nil then return { 'Loading catalog estimates…' } end
  if rows == false then return { 'Table estimates unavailable (check catalog permissions).' } end
  if #rows == 0 then return { 'No table estimates found.' } end
  return bar_rows(rows, width, 'Top tables by estimated row count')
end

local function pinned_tables(names, rows, width, chart)
  if #names == 0 then return { 'Pin a table in explorer with <leader>dp' } end
  local body = {}
  local estimates = {}
  for _, row in ipairs(type(rows) == 'table' and rows or {}) do
    estimates[row.name] = row.count
    local bare_name = row.name:match('^[^.]+%.(.+)$')
    if bare_name then estimates[bare_name] = (estimates[bare_name] or 0) + row.count end
  end
  for i, name in ipairs(names) do
    if chart then
      body[#body + 1] = { name = name, count = estimates[name] }
    else
      body[#body + 1] = name
      if i < #names then body[#body + 1] = '' end
    end
  end
  if chart then
    local heading = rows == nil and 'Loading pinned estimates…'
      or rows == false and 'Estimates unavailable' or 'Estimated rows · A–Z'
    return bar_rows(body, width, heading)
  end
  return body
end

local function format_size(kb)
  if kb >= 1024 * 1024 then return string.format('%.1f GB', kb / (1024 * 1024)) end
  if kb >= 1024 then return string.format('%.1f MB', kb / 1024) end
  return format_count(kb) .. ' kB'
end

---Keep bare explorer names usable even though SQL Server returns schema names.
local function detail_lookup(rows)
  local lookup = {}
  for _, row in ipairs(type(rows) == 'table' and rows or {}) do
    lookup[row.name] = row
    local bare = row.name:match('^[^.]+%.(.+)$')
    if bare then
      local combined = lookup[bare] or { columns = 0, indexes = 0, data_kb = 0 }
      for _, field in ipairs({ 'columns', 'indexes', 'data_kb' }) do
        combined[field] = combined[field] + row[field]
      end
      lookup[bare] = combined
    end
  end
  return lookup
end

local function metric_body(pins, details, field, width)
  local body = { details == nil and 'Loading catalog metadata…'
    or details == false and 'Catalog metadata unavailable' or 'SQL Server catalog' }
  local lookup = detail_lookup(details)
  local values = {}
  local longest = 3
  for _, name in ipairs(pins) do
    local row = lookup[name]
    local value = row and (field == 'data_kb' and format_size(row[field]) or format_count(row[field])) or 'N/A'
    values[#values + 1] = value
    longest = math.max(longest, vim.fn.strdisplaywidth(value))
  end
  local name_width = math.max(1, width - 6 - longest - 2)
  for i, name in ipairs(pins) do
    body[#body + 1] = fit(name, name_width) .. '  '
      .. string.rep(' ', longest - vim.fn.strdisplaywidth(values[i])) .. values[i]
    if i < #pins then body[#body + 1] = '' end
  end
  return body
end

local function highlight_borders(buf, content, first, padding, border_group)
  local config = require('enhance').config
  local group = border_group or (config.ui and config.ui.dashboard and config.ui.dashboard.card_border)
    or 'EnhanceDashboardBorder'
  for index, line in ipairs(content) do
    if line:find('│', 1, true) or line:find('╭', 1, true) or line:find('╰', 1, true) then
      local pos = 1
      while pos <= #line do
        local start = line:find('╭', pos, true) or line:find('╰', pos, true)
        if not start then break end
        local finish = line:find('╮', start, true) or line:find('╯', start, true)
        if not finish then break end
        vim.api.nvim_buf_add_highlight(buf, namespace, group, first + index - 1,
          padding + start - 1, padding + finish + 2)
        pos = finish + 3
      end
      pos = 1
      while true do
        local at = line:find('│', pos, true)
        if not at then break end
        vim.api.nvim_buf_add_highlight(buf, namespace, group, first + index - 1,
          padding + at - 1, padding + at + 2)
        pos = at + 3
      end
    end
  end
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

local function render(win, subtitle, details, actions, top, heading, border_group)
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
  if top then highlight_borders(buf, content, first, padding, border_group) end
  for i = 0, #banner - 1 do
    vim.api.nvim_buf_add_highlight(buf, namespace, 'Title', first + i, padding, -1)
  end
  vim.api.nvim_buf_add_highlight(buf, namespace, 'Comment', first + subtitle_index, padding, -1)
  vim.api.nvim_buf_add_highlight(buf, namespace, 'Title', first + actions_index, padding, -1)
  if top then
    for index, line in ipairs(content) do
      if line:match('^DATABASE OBJECTS') or line:match('^ROWS PER TABLE')
        or line:match('^PINNED METADATA') or line:match('^CREATE TABLE$')
        or line:match('^REFERENCES') then
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
---@param pins string[]? Pinned table names
---@param pinned_rows table[]|false? SQL Server estimates for pinned tables
---@param pinned_details table[]|false? SQL Server metadata for pinned tables
---@param database_size integer|false? SQL Server used data-file space in kB
---@return integer
function M.show_dashboard(win, connection, tables, view_count, row_counts, local_counts, pins, pinned_rows, pinned_details, database_size)
  local_counts = local_counts or {}
  pins = vim.deepcopy(pins or {})
  table.sort(pins, function(a, b)
    local left, right = a:lower(), b:lower()
    return left == right and a < b or left < right
  end)
  local width = math.max(24, vim.api.nvim_win_get_width(win) - 4)
  local columns = width >= 112 and 4 or (width >= 52 and 2 or 1)
  local card_width = math.floor((width - 2 * (columns - 1)) / columns)
  local db_type = connection.type:lower():gsub('[%s%-_]', '')
  local sqlserver = db_type == 'sqlserver' or db_type == 'mssql'
  local cards = {
    panel('TABLES', { tostring(#tables) .. ' tables' }, card_width),
    panel('VIEWS', { view_count and tostring(view_count) .. ' views' or 'Not available' }, card_width),
    panel('SAVED QUERIES', { tostring(local_counts.saved_queries or 0) .. ' saved' }, card_width),
    panel('TEMP BUFFERS', { tostring(local_counts.temp_buffers or 0) .. ' on disk' }, card_width),
    panel('ENGINE', { connection.type }, card_width),
    panel('STATUS', { 'Connected' }, card_width),
  }
  if sqlserver then
    local size = database_size == nil and 'Loading…'
      or database_size == false and 'Unavailable' or format_size(database_size)
    cards[#cards + 1] = panel('DATABASE DATA SIZE', { size }, card_width)
  end

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
  if sqlserver then
    details[#details + 1] = 'ROWS PER TABLE'
    local chart_columns = width >= 64 and 2 or 1
    local chart_width = math.floor((width - 2 * (chart_columns - 1)) / chart_columns)
    local chart = row_chart(row_counts, chart_width)
    local pinned = pinned_tables(pins, pinned_rows, chart_width, true)
    if chart_columns == 2 then
      local height = math.max(#chart, #pinned)
      while #chart < height do chart[#chart + 1] = '' end
      while #pinned < height do pinned[#pinned + 1] = '' end
    end
    vim.list_extend(details, join_panels({
      panel('ESTIMATED ROWS  ·  TOP 8', chart, chart_width),
      panel('PINNED TABLES  ·  ' .. #pins .. '/8', pinned, chart_width),
    }, chart_columns))
    if #pins > 0 then
      details[#details + 1] = 'PINNED METADATA'
      local metric_columns = width >= 112 and 3 or 1
      local metric_width = math.floor((width - 2 * (metric_columns - 1)) / metric_columns)
      local metric_panels = {}
      for _, metric in ipairs({
        { title = 'COLUMNS', field = 'columns' },
        { title = 'INDEXES', field = 'indexes' },
        { title = 'DATA SIZE', field = 'data_kb' },
      }) do
        metric_panels[#metric_panels + 1] = panel(metric.title,
          metric_body(pins, pinned_details, metric.field, metric_width), metric_width)
      end
      vim.list_extend(details, join_panels(metric_panels, metric_columns))
    end
  else
    details[#details + 1] = 'PINNED TABLES'
    vim.list_extend(details, panel('PINNED TABLES  ·  ' .. #pins .. '/8',
      pinned_tables(pins, pinned_rows, width), width))
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

---Show a SQL Server table's metrics, generated schema, and navigable references.
---@param win integer
---@param connection table
---@param name string
---@param state table {rows, metrics, script, references, saved}
---@param open_reference fun(reference: table)
---@param refresh fun()
---@return integer
function M.show_table_dashboard(win, connection, name, state, open_reference, refresh)
  local width = math.max(24, vim.api.nvim_win_get_width(win) - 4)
  local columns = width >= 112 and 4 or (width >= 52 and 2 or 1)
  local card_width = math.floor((width - 2 * (columns - 1)) / columns)
  local function value(source, field, formatter)
    if source == nil then return 'Loading…' end
    if source == false then return 'Unavailable' end
    if not source[field] then return 'N/A' end
    return formatter(source[field])
  end
  local cards = {
    panel('ROW COUNT  󰓫', { value(state.rows, 'count', format_count), 'Catalog estimate' }, card_width),
    panel('INDEXES  󰆼', { value(state.metrics, 'indexes', format_count), 'Non-heap indexes' }, card_width),
    panel('COLUMNS  󰕮', { value(state.metrics, 'columns', format_count), 'Table columns' }, card_width),
    panel('TABLE SIZE  󰉋', { value(state.metrics, 'data_kb', format_size), 'Allocated data pages' }, card_width),
  }
  local details = { 'TABLE METADATA' }
  vim.list_extend(details, join_panels(cards, columns))
  details[#details + 1] = 'CREATE TABLE'
  local script = state.script == nil and 'Loading table schema…'
    or state.script == false and 'Table schema unavailable' or state.script
  local script_body = {}
  for _, line in ipairs(vim.split(script, '\n', { plain = true })) do
    if line == '' then
      script_body[#script_body + 1] = ''
    else
      local max_width = width - 6
      while vim.fn.strdisplaywidth(line) > max_width do
        script_body[#script_body + 1] = vim.fn.strcharpart(line, 0, max_width)
        line = vim.fn.strcharpart(line, max_width)
      end
      script_body[#script_body + 1] = line
    end
  end
  vim.list_extend(details, hinted_panel('SQL SERVER  ·  generated schema', script_body, width, 'yc copy'))
  details[#details + 1] = ''
  details[#details + 1] = 'REFERENCES'
  local refs = {}
  for _, ref in ipairs(type(state.references) == 'table' and state.references or {}) do refs[#refs + 1] = ref end
  for _, ref in ipairs(state.saved or {}) do refs[#refs + 1] = ref end
  table.sort(refs, function(a, b)
    return a.kind == b.kind and a.name:lower() < b.name:lower() or a.kind < b.kind
  end)
  local ref_body = {}
  if state.references == nil then ref_body[#ref_body + 1] = 'Searching database objects…' end
  if state.references == false then ref_body[#ref_body + 1] = 'Database references unavailable' end
  for _, ref in ipairs(refs) do
    ref_body[#ref_body + 1] = (reference_icons[ref.kind] or '•') .. '  ' .. ref.name
  end
  if #ref_body == 0 then ref_body[1] = 'No references found' end
  vim.list_extend(details, reference_panel(ref_body, width))
  local buf = render(win, connection.name .. '  |  TABLE DASHBOARD', details, {
    'r   Refresh', '<CR>   Open', '?   Help',
  }, true, name, 'EnhanceDashboardTableBorder')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local function color(row, col, text, group)
    vim.api.nvim_buf_add_highlight(buf, namespace, group, row - 1, col - 1, col - 1 + #text)
  end
  local card_labels = {
    'ROW COUNT  󰓫', 'INDEXES  󰆼', 'COLUMNS  󰕮', 'TABLE SIZE  󰉋',
    'SQL SERVER  ·  generated schema',
  }
  local descriptions = {
    'Catalog estimate', 'Non-heap indexes', 'Table columns', 'Allocated data pages',
  }
  for i, line in ipairs(lines) do
    for _, category in ipairs({ 'TABLE METADATA', 'CREATE TABLE', 'REFERENCES' }) do
      local col = line:find(category, 1, true)
      if col and line:sub(1, col - 1):match('^%s*$') then
        color(i, col, category, 'EnhanceDashboardCategory')
      end
    end
    for _, label in ipairs(card_labels) do
      local col = line:find(label, 1, true)
      if col then color(i, col, label, 'EnhanceDashboardLabel') end
    end
    for _, description in ipairs(descriptions) do
      local col = line:find(description, 1, true)
      if col then color(i, col, description, 'EnhanceDashboardMetaDescription') end
    end
    if line:find('╭', 1, true) then
      local hint = line:find('<CR> to select', 1, true)
      if hint then color(i, hint, '<CR> to select', 'EnhanceDashboardHint') end
      local copy = line:find('yc copy', 1, true)
      if copy then color(i, copy, 'yc copy', 'EnhanceDashboardHint') end
    end
  end
  for i, line in ipairs(lines) do
    if line:find('│  SQL SERVER', 1, true) then
      for offset, code in ipairs(script_body) do
        local row = lines[i + 1 + offset]
        local border = row and row:find('│  ', 1, true)
        if border and code ~= '' then
          highlight_sql_line(buf, i + offset, code, border - 1 + #'│  ')
        end
      end
      break
    end
  end
  local ref_lines, next_ref = {}, 1
  for i, line in ipairs(lines) do
    local ref = refs[next_ref]
    if ref then
      local icon = reference_icons[ref.kind] or '•'
      local prefix = '│  ' .. icon .. '  '
      local start = line:find(prefix, 1, true)
      if start then
        local col = start - 1 + #'│  '
        ref_lines[i] = { reference = ref, first = col, last = col + #icon + #'  ' + #ref.name }
        vim.api.nvim_buf_add_highlight(buf, namespace, 'Special', i - 1, col, col + #icon)
        next_ref = next_ref + 1
      end
    end
  end
  local selection_ns = vim.api.nvim_create_namespace('enhance_landing_reference_selection')
  local function highlight_reference()
    vim.api.nvim_buf_clear_namespace(buf, selection_ns, 0, -1)
    if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf
      or vim.api.nvim_get_current_win() ~= win then return end
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local item = ref_lines[row]
    if item then
      vim.api.nvim_buf_set_extmark(buf, selection_ns, row - 1, item.first, {
        end_col = item.last, hl_group = 'EnhanceDashboardReferenceSelected',
        hl_mode = 'combine', priority = 110,
      })
    end
  end
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufEnter', 'WinEnter' }, {
    buffer = buf, callback = highlight_reference,
  })
  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = buf, callback = function() vim.api.nvim_buf_clear_namespace(buf, selection_ns, 0, -1) end,
  })
  highlight_reference()
  vim.keymap.set('n', '<CR>', function()
    local item = ref_lines[vim.api.nvim_win_get_cursor(win)[1]]
    if item then open_reference(item.reference) end
  end, { buffer = buf, desc = 'Open table reference in editor' })
  vim.keymap.set('n', 'yc', function()
    if type(state.script) ~= 'string' then
      vim.notify('Table schema is not available to copy', vim.log.levels.WARN)
      return
    end
    vim.fn.setreg('+', state.script)
    vim.notify('CREATE TABLE script copied to clipboard', vim.log.levels.INFO)
  end, { buffer = buf, desc = 'Copy CREATE TABLE script to clipboard' })
  vim.keymap.set('n', 'r', refresh, { buffer = buf, desc = 'Refresh table dashboard' })
  vim.keymap.set('n', '?', function() vim.cmd('help enhance') end,
    { buffer = buf, desc = 'Enhance help' })
  return buf
end

M._panel = panel

return M
