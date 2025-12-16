# DBEnhance.nvim - Exploration Findings

**Date**: 2025-12-02  
**Agent**: ML (Mel)  
**Status**: Initial Architecture Analysis

## Project Goals

### Primary Objectives
1. **Fix/Enhance Current UX Issues**
   - SQL Server column width control (long text fields go full width)
   - Customizable keymaps (`:w` for save, `<F5>` for execute - no capitals)
   - Result metadata positioning (move from bottom to status line)

2. **New Enhancements**
   - Display data types next to field names: `FieldName (varchar)`
   - Recognize JSON fields (detect `{...}` content)
   - Interactive JSON field viewing (keymap to open formatted JSON in floating window)

### User Context
- **Primary Use Case**: 80% of work involves reviewing JSON content in SQL Server
- **Workflow**: Ad-hoc queries primarily, loves saved queries system
- **Database**: Nearly exclusively SQL Server
- **Goal**: Personal use with 6-AC quality standards (potential community release)

### Approach Strategy
1. **Try extending dadbod-ui first** (preferred)
2. **Fall back to replacement** if extension proves too difficult
3. **Keep vim-dadbod backend** (not rewriting everything)

---

## Architecture Analysis

### vim-dadbod (Backend)
**Location**: `~/.local/share/nvim/lazy/vim-dadbod/`

**Key Files**:
- `autoload/db/adapter/sqlserver.vim` - SQL Server adapter
- `autoload/db/adapter.vim` - Core adapter interface
- `autoload/db/url.vim` - Connection URL parsing

**SQL Server Adapter Capabilities**:
- Uses `sqlcmd` CLI tool for execution
- Supports authentication, encryption, trust server certificate flags
- Provides completion for databases and tables
- Query execution via `db#adapter#sqlserver#input(url, input_file)`

**Key Insight**: 
- Dadbod is a thin wrapper around database CLI tools
- Results are raw output from `sqlcmd` - **no post-processing**
- Column width issue likely comes from `sqlcmd` output format, not dadbod

### vim-dadbod-ui (Frontend)
**Location**: `~/.local/share/nvim/lazy/vim-dadbod-ui/`

**Key Files**:
- `autoload/db_ui/query.vim` (432 lines) - Query execution and buffer management
- `autoload/db_ui/dbout.vim` - Result buffer handling and cell operations
- `ftplugin/sql.vim` - SQL buffer keymaps
- `ftplugin/dbout.vim` - Result buffer keymaps

**Current Keymaps** (from `ftplugin/sql.vim`):
```vim
<Leader>W - Save Query (DBUI_SaveQuery)
<Leader>E - Edit Bind Parameters (DBUI_EditBindParameters)
<Leader>S - Execute Query (DBUI_ExecuteQuery) - normal and visual mode
```

**Result Buffer Keymaps** (from `ftplugin/dbout.vim`):
```vim
<C-]>     - Jump to Foreign Key
vic       - Yank Cell Value
yh        - Yank Header
<Leader>R - Toggle Result Layout
```

**Query Execution Flow**:
1. User triggers `<Leader>S` in SQL buffer
2. `db_ui#query#execute_query()` called
3. Lines extracted (whole buffer or visual selection)
4. Bind parameters injected if needed
5. Executes via `:DB` command (from vim-dadbod)
6. Results displayed in `dbout` filetype buffer
7. Query time tracked via autocmd events (`DBExecutePre`/`DBExecutePost`)

**Result Display**:
- Results are displayed as-is from database CLI output
- Folding support for result sets (fold expression in `dbout.vim`)
- Cell navigation based on parsing table borders (`---` lines)
- **No column width control** - displays raw CLI output

---

## Feasibility Assessment

### 1. Custom Keymaps ✅ **EASY**
**Feasibility**: Very easy via configuration

**Approach**:
```lua
-- Disable default mappings
vim.g.db_ui_disable_mappings_sql = 1

-- Set custom mappings in after/ftplugin/sql.lua
vim.keymap.set('n', '<F5>', '<Plug>(DBUI_ExecuteQuery)', { buffer = true })
vim.keymap.set('v', '<F5>', '<Plug>(DBUI_ExecuteQuery)', { buffer = true })
-- Note: :w for save requires buffer-local override
```

**Extension Point**: `g:db_ui_disable_mappings_sql` variable exists for this purpose

### 2. Column Width Control ⚠️ **MODERATE-HARD**
**Problem**: Results are raw `sqlcmd` output - dadbod-ui doesn't process them

**Current Flow**:
```
sqlcmd → raw text output → vim buffer (dbout filetype)
```

**Possible Solutions**:

**Option A: Post-process sqlcmd output** (Extension approach)
- Hook into result display before buffer creation
- Parse table format, truncate columns, reformat
- **Challenge**: Need to find the right hook point in dadbod-ui

**Option B: Custom result renderer** (Replacement approach)
- Intercept `:DB` command results
- Parse into structured data
- Render with custom column widths
- **Challenge**: Requires understanding dadbod's `:DB` command internals

**Option C: Modify sqlcmd parameters**
- Use `sqlcmd -w` flag to set column width
- **Limitation**: Global width, not per-column control

**Recommendation**: Need to explore if dadbod-ui has hooks for result transformation

### 3. Result Metadata in Status Line ⚠️ **MODERATE**
**Current**: Query time tracked in `s:query_info` variable
**Display**: Appears to be in result buffer (need to verify exact location)

**Approach**:
- Create custom statusline for `dbout` filetype buffers
- Access `b:db` variable for connection info
- Access query timing from autocmd events
- Display row count (need to parse from results or query database)

**Extension Point**: Can set `statusline` for `dbout` filetype

### 4. Data Type Display ⚠️ **MODERATE-HARD**
**Goal**: Show `FieldName (varchar)` in result headers

**Challenge**:
- `sqlcmd` output doesn't include data types in results
- Would need separate query to get column metadata
- SQL Server: `SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ?`

**Possible Approaches**:

**Option A: Pre-query metadata**
- Before executing main query, detect table references
- Query `INFORMATION_SCHEMA.COLUMNS` for data types
- Merge with result display
- **Challenge**: Complex query parsing, multiple tables, joins, etc.

**Option B: Modify result header**
- Parse result headers from `sqlcmd` output
- Query metadata for detected columns
- Rewrite header line with data types
- **Challenge**: Column name ambiguity (which table?)

**Recommendation**: This is complex - might be better as v2.0 feature

### 5. JSON Field Detection & Interactive Viewing ✅ **MODERATE**
**Goal**:
- Detect fields containing JSON (`{...}`)
- Truncate JSON in display
- Keymap to open formatted JSON in floating window

**Approach**:

**Detection**:
```lua
-- In result buffer, check cell content
local cell_value = get_cell_value_under_cursor()
if cell_value:match('^%s*{.*}%s*$') then
  -- It's JSON
end
```

**Truncation**:
- Post-process result buffer after display
- Find JSON cells, replace with truncated version + indicator
- Store full content in buffer variable

**Interactive Viewing**:
```lua
-- Custom keymap in dbout buffer
vim.keymap.set('n', '<leader>jv', function()
  local cell = get_cell_value()
  if is_json(cell) then
    open_json_float(cell)
  end
end, { buffer = true })
```

**Extension Point**:
- Can add custom keymaps to `dbout` buffers
- Can use `vim.api.nvim_open_win()` for floating window
- Can use `vim.fn.json_decode()` and pretty-print

---

## Extension Points Discovered

### Configuration Variables
- `g:db_ui_disable_mappings` - Disable all default mappings
- `g:db_ui_disable_mappings_sql` - Disable SQL buffer mappings only
- `g:db_ui_disable_mappings_dbout` - Disable result buffer mappings only
- `g:db_ui_use_nerd_fonts` - Enable nerd font icons
- `g:db_ui_auto_execute_table_helpers` - Auto-execute helper queries
- `g:db_ui_execute_on_save` - Execute query on buffer save
- `g:Db_ui_buffer_name_generator` - Custom buffer naming function

### Autocmd Events
- `User *DBExecutePre` - Before query execution
- `User *DBExecutePost` - After query execution
- `User DBQueryPre` - Before DB query
- `User DBQueryPost` - After DB query

### Buffer Variables (in result buffers)
- `b:db` - Database connection info
- `b:dbui_db_key_name` - Database key name
- `b:db_ui_expanded_layout` - Layout toggle state
- `b:dbui_bind_params` - Bind parameter values

### Filetype-specific Hooks
- `ftplugin/sql.vim` - SQL query buffer setup
- `ftplugin/dbout.vim` - Result buffer setup
- Can create `after/ftplugin/sql.lua` and `after/ftplugin/dbout.lua` for extensions

---

## Recommended Approach

### Phase 1: Quick Wins (Extension) ✅
**Effort**: Low | **Impact**: High

1. **Custom Keymaps**
   - Create `after/ftplugin/sql.lua` with custom mappings
   - `:w` for save, `<F5>` for execute
   - **Estimated**: 30 minutes

2. **JSON Interactive Viewing**
   - Create `after/ftplugin/dbout.lua`
   - Add keymap for JSON popup
   - Detect JSON, format, display in floating window
   - **Estimated**: 2-3 hours

3. **Status Line Metadata**
   - Custom statusline for `dbout` buffers
   - Show query time, row count (if parseable)
   - **Estimated**: 1-2 hours

### Phase 2: Column Width (Needs Investigation) ⚠️
**Effort**: Medium-High | **Impact**: High

**Next Steps**:
1. Test if `sqlcmd -w` flag helps (global width limit)
2. Investigate dadbod's `:DB` command - can we intercept results?
3. Look for result transformation hooks in dadbod-ui
4. **Decision Point**: If no hooks exist, consider replacement approach

**Estimated Investigation**: 3-4 hours
**Estimated Implementation**: 8-12 hours (if feasible via extension)

### Phase 3: Data Type Display (Future) 🔮
**Effort**: High | **Impact**: Medium

- Complex query parsing required
- Metadata queries for every result
- Ambiguity in column sources (joins, subqueries)
- **Recommendation**: Defer to v2.0 or skip if too complex

---

## Next Actions

1. **Prototype Phase 1 features** to validate extension approach
2. **Deep dive on column width** - test sqlcmd flags, explore dadbod internals
3. **Create decision document** - extension vs replacement based on findings
4. **If extension works**: Build as `dbenhance.nvim` plugin with 6-AC standards
5. **If replacement needed**: Assess effort and decide if project is viable


