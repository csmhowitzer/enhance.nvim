# enhance.nvim Testing Guide

**Date**: 2025-12-02  
**Agent**: ML (Mel)  
**Purpose**: Manual and automated testing instructions for MVP

---

## 1. Add to Lazy.nvim Config

Add this to `~/.config/nvim/lua/plugins/dev.lua`:

```lua
{
  dir = "~/plugins/enhance.nvim",
  name = "enhance",
  -- build = ":helptags doc",  -- Uncomment when help docs are created
  config = function()
    require("enhance").setup({
      enabled = true,
      connections = {
        {
          name = "Example SQLite",
          type = "sqlite",
          path = "~/.local/share/nvim/dadbod_ui/example.db",
        }
      },
      keymaps = {
        execute_query = "<F5>",
        save_query = ":w",
      },
      ui = {
        results_position = "split", -- "split", "vsplit", "tab"
        show_query_time = true,
      },
    })
  end,
},
```

**Location**: Add after scratch-manager.nvim entry (before closing `}`)

---

## 2. Reload Neovim

```bash
# Restart Neovim or run:
:Lazy reload enhance
```

---

## 3. Manual Testing Checklist

### Test 1: Health Check ✅
```vim
:checkhealth enhance
```

**Expected output**:
- ✅ Plugin loaded successfully
- ✅ Plugin is enabled
- ✅ sqlite3 found: /Users/wwmac/anaconda3/bin/sqlite3
- ✅ 1 connection(s) configured
- ✅ Database file exists: ~/.local/share/nvim/dadbod_ui/example.db
- ✅ :EnhanceToggle available
- ✅ :EnhanceConnect available

### Test 2: Connection Browser ✅
```vim
:EnhanceConnect
```

**Expected behavior**:
1. Opens vsplit with connection list
2. Shows "Example SQLite (sqlite)" with connection number
3. Press `<CR>` to connect
4. Should open query buffer in split

### Test 3: Query Buffer ✅
After connecting (Test 2):

**Expected behavior**:
1. Buffer named `[enhance] Example SQLite`
2. Filetype is `sql`
3. Header comments explaining keymaps
4. Cursor positioned after header

### Test 4: Execute Simple Query ✅
In query buffer, type:

```sql
SELECT * FROM sqlite_master WHERE type='table';
```

Press `<F5>` in normal mode.

**Expected behavior**:
1. Notification: "Executing query..."
2. Results buffer opens in split
3. Shows table list with columns
4. Shows query timing at bottom
5. Shows database name

### Test 5: Execute Visual Selection ✅
In query buffer, type multiple queries:

```sql
SELECT 'First query' as test;
SELECT 'Second query' as test;
```

Visual select first line, press `<F5>`.

**Expected behavior**:
- Only first query executes
- Results show "First query"

### Test 6: Toggle Plugin ✅
```vim
:EnhanceToggle
```

**Expected behavior**:
- Notification: "enhance.nvim disabled"
- Run again: "enhance.nvim enabled"

### Test 7: Results Buffer Keymaps ✅
In results buffer:

- Press `q` → Should close results buffer
- Press `r` → Should show "Refresh not yet implemented" (TODO)

---

## 4. Automated Testing (Plenary)

### Run All Tests
```bash
cd ~/plugins/enhance.nvim
nvim --headless -c "PlenaryBustedDirectory tests" -c "qa!" > test_output.log 2>&1
cat test_output.log
```

### Run Single Test File
```bash
nvim --headless -c "PlenaryBustedFile tests/config_spec.lua" -c "qa!" > test_output.log 2>&1
cat test_output.log
```

### Expected Test Results
```
Testing: .../enhance.nvim/tests/config_spec.lua
  enhance.config
    defaults
      ✓ should return default configuration
    validate_connection
      ✓ should validate SQLite connection
      ✓ should reject connection without name
      ✓ should reject connection without type
      ✓ should reject SQLite connection without path
    validate_config
      ✓ should validate config with valid connections
      ✓ should reject config with invalid connection
    merge
      ✓ should merge user config with defaults
      ✓ should handle nil user config

Success: 9 / 9
```

---

## 5. Troubleshooting

### Issue: Plugin not loading
**Check**:
```vim
:lua print(vim.inspect(require("enhance")))
```
Should show module table, not error.

### Issue: sqlite3 not found
**Check**:
```bash
which sqlite3
```
Should show: `/Users/wwmac/anaconda3/bin/sqlite3`

### Issue: Database file not found
**Check**:
```bash
ls -la ~/.local/share/nvim/dadbod_ui/example.db
```
Should exist. If not, create test database or update path in config.

### Issue: Query execution fails
**Check**:
1. Run `:messages` to see error details
2. Verify database file is readable
3. Try query manually: `sqlite3 ~/.local/share/nvim/dadbod_ui/example.db "SELECT 1;"`

---

## 6. Known Limitations (MVP)

- ❌ No saved queries yet
- ❌ No query history
- ❌ No PostgreSQL/MySQL support yet
- ❌ No JSON field detection yet
- ❌ No help documentation yet
- ❌ Refresh in results buffer not implemented

---

## 7. Next Steps After Manual Testing

1. **If tests pass**: Add more test files (connections, query, executor, results)
2. **If tests fail**: Debug and fix issues
3. **After stable**: Create help documentation (6-AC #6)
4. **After 6-AC complete**: Add advanced features (JSON detection, saved queries, etc.)


