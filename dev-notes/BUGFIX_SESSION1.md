# Bug Fixes - Session 1

**Date**: 2025-12-02  
**Agent**: ML (Mel)  
**Issues Found**: Database path error, cursor position error

---

## Issues Reported by User

### 1. Database File Not Found ❌
```
ERROR Database file not found: /Users/wwmac/.local/share/nvim/dadbod_ui/example.db
```

**Root Cause**: The path pointed to a directory, not a file. The `example.db` was an empty directory.

**Fix**: 
- Created test database at `~/.local/share/nvim/enhance/test.db`
- Updated default connection path in `connections.lua`
- Database includes sample tables: `users` and `products`

### 2. Cursor Position Error ❌
```
E5108: Error executing lua: .../query.lua:38: Cursor position outside buffer
stack traceback:
  [C]: in function 'nvim_win_set_cursor'
  /Users/wwmac/plugins/enhance.nvim/lua/enhance/query.lua:38: in function 'create_query_buffer'
```

**Root Cause**: Header had 4 lines, but we tried to set cursor to line 5 (which didn't exist).

**Fix**: 
- Added extra empty line to header (now 5 lines total)
- Changed cursor position from `{#header + 1, 0}` to `{#header, 0}`
- Cursor now positions on empty line ready for typing

### 3. Duplicate Buffer Name Error ❌
```
E5108: Error executing lua: .../query.lua:19: Failed to rename buffer
stack traceback:
  [C]: in function 'nvim_buf_set_name'
  /Users/wwmac/plugins/enhance.nvim/lua/enhance/query.lua:19: in function 'create_query_buffer'
```

**Root Cause**: When user pressed `<CR>` multiple times in connection browser, we tried to create multiple buffers with the same name "[enhance] example.db". Neovim doesn't allow duplicate buffer names.

**Fix**:
- Added `find_buffer_by_name()` helper function
- Check if buffer already exists before creating new one
- If exists, switch to existing buffer instead of creating duplicate
- Show notification: "Switched to existing query buffer"

### 4. UI Wonky ⚠️
User noted UI issues but wants to fix core issues first.

**Status**: Deferred until core functionality works

---

## Files Changed

### lua/enhance/query.lua
**Line 4-53**: Added buffer reuse logic
- Added `find_buffer_by_name()` helper function
- Check for existing buffer before creating new one
- Reuse existing buffer if found

**Line 28-39**: Fixed cursor positioning
- Added empty line to header
- Changed cursor position calculation

### lua/enhance/connections.lua
**Line 17-26**: Updated default connection
- Changed path from `dadbod_ui/example.db` to `enhance/test.db`
- Changed name from "Example SQLite" to "Test SQLite"

---

## Test Database Created

**Location**: `~/.local/share/nvim/enhance/test.db`

**Schema**:
```sql
-- users table
CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Sample data: Alice, Bob, Charlie

-- products table
CREATE TABLE products (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  price REAL,
  category TEXT
);

-- Sample data: Laptop, Mouse, Desk
```

**Test Queries**:
```sql
-- List all tables
SELECT * FROM sqlite_master WHERE type='table';

-- Query users
SELECT * FROM users;

-- Query products
SELECT * FROM products;

-- Join example (if needed later)
SELECT u.name, p.name as product, p.price
FROM users u, products p
WHERE u.id <= 3 AND p.id <= 3;
```

---

## Updated Configuration

User should update `dev.lua` to use new path:

```lua
{
  dir = "~/plugins/enhance.nvim",
  name = "enhance",
  config = function()
    require("enhance").setup({
      enabled = true,
      connections = {
        {
          name = "Test SQLite",
          type = "sqlite",
          path = "~/.local/share/nvim/enhance/test.db",  -- UPDATED PATH
        }
      },
      keymaps = {
        execute_query = "<F5>",
        save_query = ":w",
      },
      ui = {
        results_position = "split",
        show_query_time = true,
      },
    })
  end,
},
```

---

## Next Steps

1. User updates config with new database path
2. Reload plugin: `:Lazy reload enhance`
3. Re-run `:checkhealth enhance` (should be all green now)
4. Test connection browser and query execution
5. Address UI issues once core functionality confirmed working


