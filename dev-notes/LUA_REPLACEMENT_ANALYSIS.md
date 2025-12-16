# Pure Lua UI Replacement - Feasibility Analysis

**Date**: 2025-12-02  
**Agent**: ML (Mel)  
**Context**: User prefers pure Lua plugins, doesn't know VimScript

## Critical Insight

Both **vim-dadbod** and **vim-dadbod-ui** are written in **VimScript**. 

**User Constraint**: Wants Neovim plugins exclusively in Lua for maintainability.

**Implication**: Extension approach would require learning/maintaining VimScript code, which conflicts with user's preference and expertise.

---

## Replacement Approach - What We'd Build

### Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    dbenhance.nvim (Lua)                 │
├─────────────────────────────────────────────────────────┤
│  • Query Buffer Management                              │
│  • Custom Keymaps (:w, <F5>)                           │
│  • Result Capture & Parsing                             │
│  • Custom Result Rendering (column width control)       │
│  • JSON Detection & Interactive Viewing                 │
│  • Saved Queries System                                 │
│  • Status Line Integration                              │
└─────────────────────────────────────────────────────────┘
                          ↓
                    Uses `:DB` command
                          ↓
┌─────────────────────────────────────────────────────────┐
│              vim-dadbod (VimScript - Keep)              │
├─────────────────────────────────────────────────────────┤
│  • Database Adapters (sqlserver, postgres, mysql, etc.) │
│  • Connection Management                                │
│  • Query Execution via CLI tools (sqlcmd, psql, etc.)  │
│  • Authentication & Connection Strings                  │
└─────────────────────────────────────────────────────────┘
```

### What We Keep (vim-dadbod)
✅ **Database adapters** - All the hard work of supporting different databases  
✅ **CLI tool wrappers** - sqlcmd, psql, mysql, etc.  
✅ **Connection management** - URL parsing, authentication  
✅ **Query execution** - The `:DB` command  

**Why**: This is the complex part. No need to rewrite.

### What We Replace (dadbod-ui → dbenhance.nvim)
🔄 **Query buffer management** - Create/manage SQL buffers  
🔄 **Result display** - Parse and render results with custom formatting  
🔄 **Saved queries** - File-based query storage and retrieval  
🔄 **UI/UX** - All keymaps, floating windows, status lines  

**Why**: This is where we add value and customize for your workflow.

---

## Technical Feasibility

### 1. Query Execution ✅ **EASY**
**Approach**: Call vim-dadbod's `:DB` command from Lua

```lua
-- Execute query and capture output
local function execute_query(db_url, query)
  -- Set up output capture
  vim.cmd('DB ' .. query)
  -- Or for file-based:
  vim.cmd('DB < ' .. query_file)
end
```

**Feasibility**: ✅ Straightforward - dadbod's `:DB` command works from Lua

### 2. Output Capture & Custom Buffer ✅ **MODERATE**
**Challenge**: Intercept `:DB` output before it goes to default buffer

**Option A: Redirect to temp file**
```lua
-- Execute with output redirection
vim.cmd('redir => g:db_output')
vim.cmd('DB ' .. query)
vim.cmd('redir END')
local output = vim.g.db_output
-- Parse and render in custom buffer
```

**Option B: Use job control**
```lua
-- Execute sqlcmd directly via vim.fn.jobstart()
local output = {}
vim.fn.jobstart({'sqlcmd', '-S', server, '-Q', query}, {
  stdout_buffered = true,
  on_stdout = function(_, data)
    output = data
  end,
  on_exit = function()
    render_results(output)
  end
})
```

**Option C: Hook into dadbod's output**
- Dadbod creates a buffer with results
- We could read that buffer and transform it
- Create our own custom buffer with formatted results

**Feasibility**: ✅ Multiple viable approaches

### 3. Result Parsing ⚠️ **MODERATE**
**Challenge**: Parse different database output formats

**SQL Server (sqlcmd) Output Format**:
```
FieldName1    FieldName2    FieldName3
------------- ------------- -------------
Value1        Value2        Value3
Value4        Value5        Value6

(2 rows affected)
```

**Parsing Strategy**:
```lua
local function parse_sqlserver_results(output)
  local lines = vim.split(output, '\n')
  local headers = {}
  local rows = {}
  local metadata = {}
  
  -- Line 1: Headers
  -- Line 2: Separator (--- lines)
  -- Line 3+: Data rows
  -- Last line: Row count
  
  -- Parse headers from separator line (column positions)
  -- Extract data based on column positions
  -- Detect JSON fields
  
  return {
    headers = headers,
    rows = rows,
    metadata = metadata
  }
end
```

**Feasibility**: ⚠️ Moderate effort - need to handle edge cases, but doable

### 4. Custom Rendering with Column Width ✅ **EASY**
**Once parsed**, rendering with custom widths is straightforward:

```lua
local function render_results(parsed, config)
  local max_widths = config.column_widths or {}
  local lines = {}
  
  -- Render headers with truncation
  for i, header in ipairs(parsed.headers) do
    local max_width = max_widths[i] or 50
    table.insert(lines, truncate(header, max_width))
  end
  
  -- Render rows
  for _, row in ipairs(parsed.rows) do
    local line = {}
    for i, cell in ipairs(row) do
      local max_width = max_widths[i] or 50
      -- Detect JSON and truncate
      if is_json(cell) then
        table.insert(line, truncate_json(cell, max_width))
      else
        table.insert(line, truncate(cell, max_width))
      end
    end
    table.insert(lines, table.concat(line, ' | '))
  end
  
  -- Set buffer content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end
```

**Feasibility**: ✅ Easy with Lua string manipulation

### 5. Saved Queries System ✅ **MODERATE**
**Approach**: File-based storage (similar to dadbod-ui)

```lua
-- Save query
local function save_query(name, content, db_key)
  local save_dir = vim.fn.stdpath('data') .. '/dbenhance/queries/' .. db_key
  vim.fn.mkdir(save_dir, 'p')
  local file = save_dir .. '/' .. name .. '.sql'
  vim.fn.writefile(vim.split(content, '\n'), file)
end

-- Load saved queries
local function get_saved_queries(db_key)
  local save_dir = vim.fn.stdpath('data') .. '/dbenhance/queries/' .. db_key
  return vim.fn.glob(save_dir .. '/*.sql', false, true)
end
```

**Feasibility**: ✅ Straightforward file operations

### 6. JSON Interactive Viewing ✅ **EASY**
**Approach**: Floating window with formatted JSON

```lua
local function show_json_popup(json_str)
  -- Parse and pretty-print
  local ok, parsed = pcall(vim.fn.json_decode, json_str)
  if not ok then
    vim.notify('Invalid JSON', vim.log.levels.ERROR)
    return
  end
  
  local formatted = vim.fn.json_encode(parsed)
  -- Split into lines with indentation
  local lines = vim.split(formatted, '\n')
  
  -- Create floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'json'
  
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 4)
  
  vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    style = 'minimal',
    border = 'rounded'
  })
end
```

**Feasibility**: ✅ Easy with modern Neovim APIs

---

## Effort Estimation

### Core Features (MVP)
| Feature | Effort | Priority | Notes |
|---------|--------|----------|-------|
| Query buffer management | 2-3 hours | High | Create/edit SQL buffers |
| Custom keymaps (`:w`, `<F5>`) | 1 hour | High | Buffer-local mappings |
| Execute via `:DB` command | 2 hours | High | Integration with dadbod |
| Output capture | 3-4 hours | High | Intercept/redirect results |
| SQL Server result parsing | 4-6 hours | High | Parse table format |
| Custom result rendering | 3-4 hours | High | Column width control |
| JSON detection & truncation | 2 hours | High | Pattern matching |
| JSON floating window | 2 hours | High | Interactive viewing |
| Status line integration | 2 hours | Medium | Query time, row count |
| **Total MVP** | **21-28 hours** | | |

### Enhanced Features (Post-MVP)
| Feature | Effort | Priority | Notes |
|---------|--------|----------|-------|
| Saved queries system | 4-6 hours | Medium | File-based storage |
| Query browser UI | 4-6 hours | Medium | Telescope/custom picker |
| Connection management | 6-8 hours | Low | Can use dadbod's for now |
| Multi-database support | 4-6 hours | Low | Postgres, MySQL parsers |
| Data type display | 12-16 hours | Low | Query analysis, metadata |
| **Total Enhanced** | **30-42 hours** | | |

### 6-AC Compliance
| Component | Effort | Notes |
|-----------|--------|-------|
| README.md | 2 hours | auto_cwd.nvim format |
| Test Suite | 8-10 hours | Plenary/Busted tests |
| Lua Annotations | 2-3 hours | Type definitions |
| User Configuration | 2 hours | setup() function |
| Health Check | 2-3 hours | `:checkhealth` integration |
| Help Documentation | 3-4 hours | Vim help docs |
| **Total 6-AC** | **19-24 hours** | | |

### Grand Total
- **MVP Only**: 21-28 hours
- **MVP + 6-AC**: 40-52 hours (production-ready)
- **Full Featured + 6-AC**: 70-94 hours (all enhancements)

---

## Comparison: Extension vs Replacement

### Extension Approach (VimScript)
**Pros**:
- Reuse existing dadbod-ui infrastructure
- Less code to write initially
- Saved queries system already exists

**Cons**:
- ❌ Requires learning/maintaining VimScript (user doesn't know it)
- ❌ Limited control over result rendering
- ❌ Harder to implement column width control
- ❌ Constrained by dadbod-ui's architecture
- ❌ May still need significant VimScript code

**Estimated Effort**: 15-25 hours (but in unfamiliar language)

### Replacement Approach (Pure Lua)
**Pros**:
- ✅ Pure Lua (user's preference and expertise)
- ✅ Full control over all features
- ✅ Modern Neovim APIs (floating windows, extmarks, etc.)
- ✅ Easier to maintain and extend
- ✅ Better string manipulation in Lua
- ✅ Can optimize for SQL Server specifically

**Cons**:
- More code to write upfront
- Need to implement saved queries system
- Need to handle result parsing ourselves

**Estimated Effort**: 40-52 hours (MVP + 6-AC)

---

## Recommendation: Pure Lua Replacement

### Why Replacement Makes Sense

1. **Language Preference**: User wants Lua-only plugins
2. **Maintainability**: User can maintain/extend Lua code
3. **Full Control**: Can implement column width control properly
4. **Modern APIs**: Use latest Neovim features
5. **SQL Server Focus**: Optimize for user's primary use case
6. **Learning Value**: Better investment of time than learning VimScript

### Phased Development Plan

**Phase 1: Core Functionality (21-28 hours)**
- Query buffer management
- Execute queries via dadbod
- Capture and parse SQL Server results
- Custom rendering with column width control
- Basic keymaps (`:w`, `<F5>`)
- JSON detection and interactive viewing
- Status line integration

**Deliverable**: Working plugin for personal use

**Phase 2: 6-AC Compliance (19-24 hours)**
- README.md
- Comprehensive test suite
- Lua annotations
- User configuration system
- Health check
- Help documentation

**Deliverable**: Production-ready, community-shareable plugin

**Phase 3: Enhanced Features (Optional, 30-42 hours)**
- Saved queries system
- Query browser UI
- Multi-database support
- Data type display (stretch goal)

**Deliverable**: Feature-complete database UI

---

## Technical Risks & Mitigations

### Risk 1: Output Capture Complexity
**Risk**: Intercepting `:DB` output might be tricky
**Mitigation**: Multiple approaches available (redir, job control, buffer reading)
**Fallback**: Execute sqlcmd directly via job control

### Risk 2: Result Parsing Edge Cases
**Risk**: SQL Server output format variations
**Mitigation**: Start with common cases, iterate based on real usage
**Fallback**: Display raw output if parsing fails

### Risk 3: Connection Management
**Risk**: Replicating dadbod's connection system is complex
**Mitigation**: Use dadbod's connection variables (`b:db`, `g:db`, etc.)
**Fallback**: Simple connection string input for MVP

### Risk 4: Multi-Database Support
**Risk**: Different databases have different output formats
**Mitigation**: Focus on SQL Server first (user's primary use case)
**Fallback**: SQL Server only for MVP, add others later

---

## Next Steps

### Option A: Prototype Core Features (Recommended)
**Goal**: Validate technical approach with working code
**Scope**:
- Execute query via dadbod
- Capture output
- Parse SQL Server results
- Render with column width control
- JSON popup

**Effort**: 8-12 hours
**Outcome**: Proof of concept, technical validation

### Option B: Full MVP Development
**Goal**: Build complete working plugin
**Scope**: All Phase 1 features
**Effort**: 21-28 hours
**Outcome**: Usable plugin for personal use

### Option C: Hybrid Approach
**Goal**: Quick wins first, then full replacement
**Scope**:
1. Implement custom keymaps as extension (2 hours)
2. Build prototype to validate replacement approach (8-12 hours)
3. Decide: continue with replacement or stick with extensions

**Effort**: 10-14 hours
**Outcome**: Immediate improvements + informed decision

---

## Questions for User

1. **Comfort with effort estimate?** 40-52 hours for production-ready Lua plugin vs 15-25 hours for VimScript extensions (but in unfamiliar language)

2. **Preferred approach?**
   - **Option A**: Prototype first (validate technical feasibility)
   - **Option B**: Full MVP development (commit to replacement)
   - **Option C**: Hybrid (quick wins + prototype)

3. **MVP scope?** Are saved queries essential for MVP, or can that be Phase 3?

4. **Connection management?** OK to use dadbod's connection system initially, or need custom UI?

5. **Multi-database support?** SQL Server only for MVP, or need Postgres/MySQL too?


