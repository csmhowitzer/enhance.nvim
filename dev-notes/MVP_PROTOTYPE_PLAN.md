# DBEnhance.nvim - MVP Prototype Plan

**Date**: 2025-12-02  
**Agent**: ML (Mel)  
**Goal**: Validate technical feasibility with minimal working prototype

## MVP Scope (User-Defined)

### Must Have
1. **DB UI Tool Appearance**
   - Buffer for connections and table explorer (like dadbod-ui)
   - Buffer for query implementation (like dadbod-ui)
   - Buffer for results

2. **Core Workflow**
   - Write a query
   - Execute it
   - See results in simple format

### Success Criteria
If we can accomplish this with **relative ease**, user is game to move forward.

---

## Technical Approach (Based on User's C# Test Pattern)

### Reference Pattern from cs_test_runner.lua

User's existing code shows the exact pattern we need:

```lua
-- Execute CLI command and capture output
vim.fn.jobstart({ "dotnet", "run", "-silent", "-ctrf", "/dev/stdout" }, {
  stdout_buffered = true,
  on_stdout = function(_, data)
    output_process(bufnr, state, data)  -- Parse and process
  end,
  on_exit = function()
    output_exit(bufnr, state)  -- Finalize
  end,
})
```

**Key insights:**
- Output redirected to `/dev/stdout` (or `/dev/null` if discarding)
- `stdout_buffered = true` - Collect all output before processing
- `on_stdout` callback - Parse and format results
- `on_exit` callback - Finalize display

### Applying to SQL Execution

```lua
-- Execute sqlcmd and capture output
local function execute_query(connection, query)
  local output_lines = {}
  
  vim.fn.jobstart({
    'sqlcmd',
    '-S', connection.server,
    '-d', connection.database,
    '-U', connection.user,
    '-P', connection.password,
    '-Q', query,
    '-h', '-1',  -- No headers in output
    '-W',        -- Remove trailing spaces
  }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      -- Capture output
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(output_lines, line)
        end
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        -- Parse and display results
        parse_and_display_results(output_lines)
      else
        vim.notify("Query failed", vim.log.levels.ERROR)
      end
    end,
  })
end
```

---

## MVP Architecture

### 1. Connection Buffer (Simple List)
**File**: `lua/dbenhance/connections.lua`

```lua
-- Simple connection list
local connections = {
  {
    name = "Local SQL Server",
    server = "localhost",
    database = "TestDB",
    user = "sa",
    password = "password"
  }
}

-- Display in buffer
local function show_connections()
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  
  for i, conn in ipairs(connections) do
    table.insert(lines, string.format("[%d] %s (%s)", i, conn.name, conn.database))
  end
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'dbenhance-connections'
  
  -- Open in split
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(0, buf)
end
```

### 2. Query Buffer (SQL Editing)
**File**: `lua/dbenhance/query.lua`

```lua
-- Create query buffer
local function create_query_buffer(connection)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = 'sql'
  
  -- Store connection info in buffer variable
  vim.b[buf].dbenhance_connection = connection
  
  -- Set keymaps
  vim.keymap.set('n', '<F5>', function()
    execute_current_query(buf)
  end, { buffer = buf })
  
  return buf
end
```

### 3. Results Buffer (Simple Display)
**File**: `lua/dbenhance/results.lua`

```lua
-- Display results in buffer
local function display_results(output_lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, output_lines)
  vim.bo[buf].filetype = 'dbenhance-results'
  vim.bo[buf].modifiable = false
  
  -- Open in horizontal split
  vim.cmd('split')
  vim.api.nvim_win_set_buf(0, buf)
end
```

### 4. Query Execution (Using jobstart pattern)
**File**: `lua/dbenhance/executor.lua`

```lua
local function execute_query(connection, query_text)
  local output_lines = {}
  local start_time = vim.loop.hrtime()
  
  vim.fn.jobstart({
    'sqlcmd',
    '-S', connection.server,
    '-d', connection.database,
    '-U', connection.user,
    '-P', connection.password,
    '-Q', query_text,
  }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(output_lines, line)
        end
      end
    end,
    on_exit = function(_, exit_code)
      local duration = (vim.loop.hrtime() - start_time) / 1000000
      
      if exit_code == 0 then
        -- Add metadata
        table.insert(output_lines, "")
        table.insert(output_lines, string.format("Query completed in %.2fms", duration))
        
        -- Display results
        require('dbenhance.results').display_results(output_lines)
      else
        vim.notify("Query execution failed", vim.log.levels.ERROR)
      end
    end,
  })
end
```

---

## MVP File Structure

```
dbenhance.nvim/
├── lua/
│   └── dbenhance/
│       ├── init.lua           # Main entry point
│       ├── connections.lua    # Connection management
│       ├── query.lua          # Query buffer management
│       ├── results.lua        # Results display
│       └── executor.lua       # Query execution via jobstart
├── plugin/
│   └── dbenhance.lua          # Plugin initialization
└── README.md                  # Basic documentation
```

---

## MVP Implementation Steps

### Step 1: Basic Plugin Structure (30 min)
- Create file structure
- Basic `init.lua` with setup function
- Plugin entry point

### Step 2: Connection Management (1 hour)
- Simple hardcoded connection list
- Connection buffer display
- Select connection keymap

### Step 3: Query Buffer (1 hour)
- Create SQL buffer with connection context
- Basic keymaps (`<F5>` for execute)
- Buffer-local connection storage

### Step 4: Query Execution (2 hours)
- Implement jobstart pattern (like cs_test_runner)
- Execute sqlcmd with connection params
- Capture stdout output
- Error handling

### Step 5: Results Display (1 hour)
- Simple buffer with raw output
- Add query timing metadata
- Basic formatting

**Total MVP Time**: ~5-6 hours

---

## Testing Plan

### Manual Testing Checklist
1. ✅ Plugin loads without errors
2. ✅ Connection buffer displays
3. ✅ Can create query buffer
4. ✅ Can write SQL query
5. ✅ `<F5>` executes query
6. ✅ Results appear in buffer
7. ✅ Query timing displayed
8. ✅ Error handling works

### Test Queries
```sql
-- Simple select
SELECT TOP 10 * FROM Users

-- With JSON field
SELECT Id, Name, JsonData FROM Products

-- Error case
SELECT * FROM NonExistentTable
```

---

## Decision Points After MVP

### If MVP Works Well ✅
**Next Steps:**
1. Add column width control (parse and reformat results)
2. Implement JSON detection and interactive viewing
3. Add saved queries system
4. Build table explorer
5. Proceed to full 6-AC development

**Estimated Additional Effort**: 35-45 hours for production-ready

### If MVP Has Issues ⚠️
**Fallback Options:**
1. Stick with dadbod-ui, implement only custom keymaps
2. Investigate alternative database CLI tools
3. Consider different architecture approach

---

## Key Advantages of This Approach

1. **Proven Pattern**: Uses exact same jobstart pattern as user's C# test runner
2. **No VimScript**: Pure Lua implementation
3. **Full Control**: Can format output however we want
4. **Simple**: Minimal complexity for MVP
5. **Extensible**: Easy to add features once core works

---

## Questions Before Starting

1. **Connection info**: Should I hardcode a test connection, or do you want to provide connection details?

2. **sqlcmd availability**: Do you have `sqlcmd` installed and accessible? (Can test with `which sqlcmd`)

3. **Start immediately**: Should I build the MVP now, or do you want to review the plan first?

4. **Test database**: Do you have a test SQL Server database I can use for queries?

---

## Next Action

**Recommended**: Build the MVP prototype (5-6 hours) to validate:
- jobstart pattern works for sqlcmd
- Output capture and display works
- Basic UI layout is acceptable
- Query execution flow feels right

**Deliverable**: Working prototype that demonstrates core workflow:
- Open connection list
- Create query buffer
- Write query
- Execute with `<F5>`
- See results

If this works smoothly, we proceed with full development. If not, we reassess.

**Ready to start?**


