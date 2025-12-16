# Technical Findings - vim-dadbod Architecture

**Date**: 2025-12-02  
**Agent**: ML (Mel)

## Key Discoveries

### 1. How vim-dadbod Works ✅

**SQLite Adapter** (`~/.local/share/nvim/lazy/vim-dadbod/autoload/db/adapter/sqlite.vim`):

```vim
function! db#adapter#sqlite#command(url) abort
  return ['sqlite3', s:path(a:url)]
endfunction

function! db#adapter#sqlite#interactive(url) abort
  return db#adapter#sqlite#command(a:url) + ['-column', '-header']
endfunction
```

**Key Insights:**
- ✅ **Uses `sqlite3` CLI tool** (not sqlcmd - that's SQL Server specific)
- ✅ **You have sqlite3 installed**: `/Users/wwmac/anaconda3/bin/sqlite3`
- ✅ **Interactive mode adds**: `-column` (columnar output) and `-header` (show headers)
- ✅ **Dadbod is just a wrapper** around database CLI tools

### 2. Your SQLite Database Location

**Found**: `/Users/wwmac/.local/share/nvim/dadbod_ui/example.db`

This is where dadbod-ui stores your test database.

### 3. Connection Storage

Dadbod uses Vim variables for connections:
- `g:dbs` - Global database connections dictionary
- `b:db` - Buffer-local database URL
- Connection URL format: `sqlite:/path/to/database.db`

Example:
```vim
let g:dbs = {
  'example': 'sqlite:~/.local/share/nvim/dadbod_ui/example.db'
}
```

### 4. How Queries Are Executed

**From the adapter code:**
1. Dadbod calls `db#adapter#sqlite#interactive(url)`
2. Returns command: `['sqlite3', '/path/to/db', '-column', '-header']`
3. Executes via Vim's `system()` or `job_start()`
4. Captures stdout output
5. Displays in buffer

**This is EXACTLY what we need to replicate in Lua!**

---

## MVP Technical Approach (Updated for SQLite)

### Execute SQLite Query (Using jobstart pattern)

```lua
local function execute_sqlite_query(db_path, query_text)
  local output_lines = {}
  local start_time = vim.loop.hrtime()
  
  vim.fn.jobstart({
    'sqlite3',
    db_path,
    '-column',    -- Columnar output
    '-header',    -- Show column headers
  }, {
    stdout_buffered = true,
    on_stdin = function(_, _, _)
      -- Send query to stdin
      return { query_text }
    end,
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
        display_results(output_lines)
      else
        vim.notify("Query execution failed", vim.log.levels.ERROR)
      end
    end,
  })
end
```

### Alternative: Direct Command Execution

```lua
-- Simpler approach for MVP
local function execute_sqlite_query_simple(db_path, query_text)
  local cmd = string.format("sqlite3 -column -header '%s' \"%s\"", db_path, query_text)
  local output = vim.fn.system(cmd)
  
  if vim.v.shell_error == 0 then
    display_results(vim.split(output, '\n'))
  else
    vim.notify("Query failed", vim.log.levels.ERROR)
  end
end
```

---

## Updated MVP Plan

### Hardcoded Connection for Testing

```lua
-- lua/dbenhance/connections.lua
local M = {}

M.connections = {
  {
    name = "Example SQLite",
    type = "sqlite",
    path = vim.fn.expand("~/.local/share/nvim/dadbod_ui/example.db"),
  }
}

function M.get_connection(name)
  for _, conn in ipairs(M.connections) do
    if conn.name == name then
      return conn
    end
  end
end

return M
```

### Test Query Examples

```sql
-- List all tables
SELECT name FROM sqlite_master WHERE type='table';

-- Simple select (if you have a users table)
SELECT * FROM users LIMIT 10;

-- Check database schema
.schema
```

---

## Next Steps

1. **Plugin Name Decision** - Need to choose a name before setting up repo
2. **Repo Setup** - Initialize plugin structure
3. **MVP Implementation** - Build prototype with SQLite support
4. **Testing** - Validate with your example.db


