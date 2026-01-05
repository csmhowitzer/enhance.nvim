# enhance.nvim

A pure Lua database interface for Neovim with intelligent result formatting and modern UI. Compatible with vim-dadbod-ui connection format.

## Features

- **Multi-database Support**: SQL Server, SQLite, MySQL, PostgreSQL
- **URL connection strings**: Uses standard database URL format for connections
- **Fast Execution**: Lightweight CLI-based query execution
- **Explorer UI**: Tree-based database browser with drawer layout
- **Syntax Highlighting**: Customize and make your SQL syntax colors come to life!
- **Temp Buffers**: Query buffers stored without needing to save 
- **Secure**: Credentials stored in external JSON file (outside version control)

<img width="2559" height="1326" alt="image" src="https://github.com/user-attachments/assets/067fdef2-ce2e-4487-b31c-6b43b5580595" />


## Requirements

### Neovim Version

- **Required**: Neovim 0.10+ (for floating window features)
- **Required**: [vim-dadbod](https://github.com/kristijanhusak/vim-dadbod) for the behind the scenes database CLI tool execution support
- **Recommended**: [vim-dadbod-completion](https://github.com/kristijanhusak/vim-dadbod-completion) for database-specific text object completions

### CLI Tools

enhance.nvim uses database CLI tools for query execution. Install the tools for your databases:

| Database | CLI Tool | Installation |
|----------|----------|--------------|
| **SQLite** | `sqlite3` | `brew install sqlite3` (macOS)<br>`apt install sqlite3` (Linux) |
| **SQL Server** | `sqlcmd` | `brew install sqlcmd` (macOS)<br>[Microsoft Docs](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility) (Windows/Linux) |
| **MySQL** | `mysql` | `brew install mysql-client` (macOS)<br>`apt install mysql-client` (Linux) |
| **PostgreSQL** | `psql` | `brew install postgresql` (macOS)<br>`apt install postgresql-client` (Linux) |

Run `:checkhealth enhance` to verify CLI tools and *vim-dadbod* are installed

## Installation

### With lazy.nvim

```lua
-- In your lua/plugins/enhance.lua or similar
return {
  {
    "kristijanhusak/vim-dadbod", -- required 
    "kristijanhusak/vim-dadbod-completion", -- optional
    "csmhowitzer/enhance.nvim",  -- or dir = "~/plugins/enhance.nvim" for local
    config = function()
      require("enhance").setup({
        enabled = true,
        -- connections_file is optional - defaults to ~/.local/share/enhance/connections.json
        -- connections_file = "~/my-custom-path/connections.json",
      })
    end,
  },
}
```

### Connections File

Create `~/.local/share/enhance/connections.json` with your database connections (vim-dadbod-ui format):

```json
[
  {
    "name": "Local SQLite",
    "url": "sqlite:/Users/yourusername/example.db"
  },
  {
    "name": "Production SQL Server",
    "url": "sqlserver://server.example.com/ProductionDB;user=admin;password=secret;TrustServerCertificate=yes;"
  }
]
```

See [Connection Format](#connection-format) for detailed examples.

## Configuration

### Basic Setup

```lua
require("enhance").setup({
  enabled = true,
  connections_file = "~/.local/share/enhance/connections.json",  -- Optional, this is the default
})
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable/disable the plugin |
| `connections_file` | string | `~/.local/share/enhance/connections.json` | Path to connections JSON file |
| `keymaps.execute_query` | string | `<F5>` | Keymap to execute query |
| `keymaps.save_query` | string | `:w` | Keymap to save query |
| `ui.results_position` | string | `"split"` | Results window position |
| `ui.show_query_time` | boolean | `true` | Show query execution time |
| `status_line.enabled` | boolean | `true` | Enable status line in results |
| `status_line.position` | string | `"top"` | Status line position: `"top"`, `"bottom"`, `"none"` |

### Connection Format

enhance.nvim uses a standard database URL connection string and a name property for the displayed name; which ends up as an array of objects with `name` and `url` fields.

**Default File Location:** `~/.local/share/enhance/connections.json` (configurable)

**Format:** Standard database connection URLs

#### SQLite

```json
{
  "name": "Local SQLite",
  "url": "sqlite:/Users/yourusername/example.db"
}
```

**URL Format:** `sqlite:/path/to/database.db`

#### SQL Server

```json
{
  "name": "Production SQL Server",
  "url": "sqlserver://server.example.com/ProductionDB;user=admin;password=secret;TrustServerCertificate=yes;"
}
```

**URL Format:** `sqlserver://host/database;param=value;param=value;`

**Parameters:**
- `user` - Username
- `password` - Password
- `TrustServerCertificate` - `yes` or `no` (default: `yes` for self-signed certs)

**Note:** Omit `user` and `password` for Windows Authentication (adds `-E` flag to sqlcmd)

#### MySQL

```json
{
  "name": "Dev MySQL",
  "url": "mysql://user:password@localhost:3306/mydb"
}
```

**URL Format:** `mysql://user:password@host:port/database`

**Defaults:** Port `3306` if omitted

#### PostgreSQL

```json
{
  "name": "Staging PostgreSQL",
  "url": "postgresql://user:password@host:5432/mydb"
}
```

**URL Format:** `postgresql://user:password@host:port/database` (or `postgres://...`)

**Defaults:** Port `5432` if omitted

### Complete Example

`~/.local/share/enhance/connections.json`:

```json
[
  {
    "name": "Local SQLite",
    "url": "sqlite:/Users/yourusername/example.db"
  },
  {
    "name": "Production SQL Server",
    "url": "sqlserver://prod-server.example.com/ProductionDB;user=admin;password=secret;TrustServerCertificate=yes;"
  },
  {
    "name": "Dev MySQL",
    "url": "mysql://dev_user:dev_password@localhost:3306/dev_db"
  },
  {
    "name": "Staging PostgreSQL",
    "url": "postgresql://staging_user:staging_password@staging-db.example.com:5432/staging_db"
  }
]
```

### Security Best Practices

1. **Keep connections.json outside version control:**
   ```bash
   echo "connections.json" >> .gitignore
   ```

2. **Set proper file permissions:**
   ```bash
   chmod 600 ~/.local/share/enhance/connections.json
   ```

3. **Use environment-specific files:**
   ```lua
   require("enhance").setup({
     connections_file = vim.fn.expand("~/.config/enhance/connections-" .. vim.env.ENV .. ".json"),
   })
   ```

4. **vim-dadbod-ui compatibility:** You can share the same connections file with vim-dadbod-ui by pointing both plugins to the same file, or vise-versa!

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:EnhanceStart` | Start enhance workspace with explorer and query editor |
| `:EnhanceStop` | Stop enhance workspace and close all windows |
| `:EnhanceExplorer` | Toggle database explorer drawer |
| `:EnhanceResults` | Toggle results window |
| `:EnhanceQuery` | Create new query buffer |
| `:EnhanceRefresh` | Refresh explorer (clear cache and redraw) |
| `:EnhanceDeleteFile [filename]` | Delete file (current buffer or specified) |
| `:EnhanceToggle` | Toggle plugin enabled/disabled |

### Workflow

1. **Start**: Run `:EnhanceStart` to open workspace with explorer drawer
2. **Connect**: Press `<CR>` on a connection in explorer to expand it
3. **New Query**: Press `<CR>` on "New Query" or run `:EnhanceQuery`
4. **Write**: Write your SQL query in the editor
5. **Execute**: Press `<F5>` to execute (normal mode: entire buffer, visual mode: selection)
6. **View**: Results appear in bottom window with status line
7. **Save**: Use `:w` to save query (prompts for filename)
8. **Manage**: Use explorer to view buffers, saved queries, and tables

### Keymaps

**Explorer:**
- `<CR>` - Expand/collapse connection or open item
- `q` - Close explorer
- `<leader>de` - Toggle explorer
- `R` - Refresh explorer (clear cache and redraw)
- `dd` or `D` - Delete file under cursor
- `d` or `D` (visual) - Delete selected files

**Query Buffer:**
- `<F5>` - Execute query (normal mode: entire buffer, visual mode: selection)
- `:w` - Save query (prompts for filename if new)

**Results Buffer:**
- `q` - Close results window
- Normal scrolling (`j`, `k`, `Ctrl-d`, `Ctrl-u`) - Navigate results

### Features

#### Visual Selection Execution

Select specific SQL statements and execute only the selection:

```sql
-- Select just the DROP statement and press <F5>
CREATE TABLE TestTable (id INTEGER PRIMARY KEY);

DROP TABLE TestTable;  -- Highlight this line in visual mode
```

#### Auto-Refresh on DDL

Explorer automatically refreshes when you execute DDL statements:
- `CREATE TABLE` - New table appears in explorer
- `DROP TABLE` - Table disappears from explorer
- `ALTER TABLE` - Changes reflected immediately

#### Smart Result Messages

**DML Statements** show clear success messages with row counts:

*INSERT:*
```
✓ Inserted 5 rows
```

*UPDATE:*
```
✓ Updated 3 rows
```

*DELETE:*
```
✓ Deleted 2 rows
```

**DDL Statements** show operation-specific success messages:

*CREATE TABLE:*
```
✓ Table created successfully
```

*DROP TABLE:*
```
✓ Table dropped successfully
```

*ALTER TABLE:*
```
✓ Table altered successfully
```

**SELECT Statements:**
```
Rows: 5 | 10.02ms | example.db | sqlite | 2025-12-17 22:04:38
─────────────────────────────────────────────────────────────
id  name       email
--  ---------  ------------------
1   John Doe   john@example.com
2   Jane Doe   jane@example.com
```

## Customization

### Syntax Highlighting

enhance.nvim provides granular highlight groups for the results status line:

```lua
-- Default highlight groups (Catppuccin Mocha colors)
vim.api.nvim_set_hl(0, 'EnhanceStatusLabel', { fg = '#89b4fa' })      -- Light blue
vim.api.nvim_set_hl(0, 'EnhanceStatusValue', { fg = '#cdd6f4' })      -- Light gray
vim.api.nvim_set_hl(0, 'EnhanceStatusConnection', { fg = '#a6e3a1' }) -- Green
vim.api.nvim_set_hl(0, 'EnhanceStatusDBType', { fg = '#f9e2af' })     -- Yellow
vim.api.nvim_set_hl(0, 'EnhanceStatusTimestamp', { fg = '#94e2d5' })  -- Teal
vim.api.nvim_set_hl(0, 'EnhanceStatusSeparator', { fg = '#6c7086' })  -- Gray
vim.api.nvim_set_hl(0, 'EnhanceLineNumber', { fg = '#6c7086' })       -- Gray
vim.api.nvim_set_hl(0, 'EnhanceLineNumberAccent', { fg = '#89b4fa' }) -- Light blue (every 5th line)
vim.api.nvim_set_hl(0, 'EnhanceCursorLine', { bg = '#2a2b3c' })       -- Subtle background
vim.api.nvim_set_hl(0, 'EnhanceCursorLineAccent', { bg = '#3f3144' }) -- Purple-tinted (every 5th line)
```

**Customize in your config:**

```lua
-- After colorscheme is loaded
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    vim.api.nvim_set_hl(0, 'EnhanceStatusLabel', { fg = '#your-color' })
    vim.api.nvim_set_hl(0, 'EnhanceStatusValue', { fg = '#your-color' })
    -- ... customize other groups
  end,
})
```

**Configure highlight groups in setup:**

```lua
require("enhance").setup({
  status_line = {
    enabled = true,
    position = "top",  -- "top", "bottom", or "none"
    highlights = {
      label = "EnhanceStatusLabel",
      value = "EnhanceStatusValue",
      connection = "EnhanceStatusConnection",
      db_type = "EnhanceStatusDBType",
      timestamp = "EnhanceStatusTimestamp",
      separator = "EnhanceStatusSeparator",
      line_number = "EnhanceLineNumber",
      line_number_accent = "EnhanceLineNumberAccent",
    },
  },
})
```

## Examples

### Basic SQLite Workflow

```bash
# 1. Create connections file
mkdir -p ~/.local/share/enhance
cat > ~/.local/share/enhance/connections.json << 'EOF'
[
  {
    "name": "My App DB",
    "url": "sqlite:/Users/yourusername/myapp.db"
  }
]
EOF

# 2. Configure plugin (in your Neovim config)
require("enhance").setup({
  enabled = true,
})

# 3. Start workspace
:EnhanceStart

# 4. Expand connection in explorer (press <CR>)
# 5. Create new query (press <CR> on "New Query")
# 6. Write query:
SELECT * FROM users WHERE active = 1;

# 7. Execute (press <F5>)
# 8. Save query (press :w, enter filename "active_users")
```

### Multiple Database Connections

```json
[
  {
    "name": "Local Development",
    "url": "sqlite:/Users/yourusername/dev.db"
  },
  {
    "name": "Production SQL Server",
    "url": "sqlserver://prod-server.example.com/ProductionDB;user=admin;password=secret;TrustServerCertificate=yes;"
  },
  {
    "name": "Staging MySQL",
    "url": "mysql://staging_user:staging_password@staging-db.example.com:3306/staging_db"
  }
]
```

### Bulk File Deletion

1. Open explorer (`:EnhanceExplorer`)
2. Navigate to Buffers or Saved Queries section
3. Enter visual mode (`V`)
4. Select multiple files
5. Press `d` to delete all selected files

## Troubleshooting

### Database CLI tools not found

**Problem**: `:checkhealth enhance` shows CLI tools missing

**Solution**: Install required tools (see [Requirements](#requirements))

### Connections file not found

**Problem**: "Connections file not found" error on startup

**Solution**:
```bash
# Create the directory
mkdir -p ~/.local/share/enhance

# Create connections file
cat > ~/.local/share/enhance/connections.json << 'EOF'
[
  {
    "name": "example",
    "url": "sqlite:/path/to/your/database.db"
  }
]
EOF
```

### No connections in explorer

**Problem**: Explorer shows empty connection list

**Solution**:
1. Verify connections file exists: `cat ~/.local/share/enhance/connections.json`
2. Check JSON syntax is valid (use `jq` or online validator)
3. Run `:messages` to see error details
4. Verify file path in config matches actual file location

### Query execution fails

**Problem**: Query executes but shows no results or errors

**Solution**:
1. Check `:checkhealth enhance` for connection issues
2. Verify database file exists (for SQLite): `ls -la /path/to/db.db`
3. Test connection manually:
   - SQLite: `sqlite3 /path/to/db.db "SELECT 1;"`
   - SQL Server: `sqlcmd -S server -d database -U user -P password -Q "SELECT 1;"`
   - MySQL: `mysql -h host -u user -ppassword database -e "SELECT 1;"`
   - PostgreSQL: `psql "host=host dbname=database user=user password=password" -c "SELECT 1;"`
4. Check query syntax in database-specific tool first

### SQL Server certificate errors

**Problem**: "SSL Provider: The certificate chain was issued by an authority that is not trusted"

**Solution**: Add `TrustServerCertificate=yes` to your connection URL:
```json
{
  "url": "sqlserver://server/database;user=admin;password=secret;TrustServerCertificate=yes;"
}
```

### Explorer not showing buffers

**Problem**: Buffers section shows (0) even with open query buffers

**Solution**: Buffers are only tracked after executing a query. Execute a query first, then the buffer will appear in the explorer.

### Tables not refreshing after DDL

**Problem**: Created table doesn't appear in explorer

**Solution**:
- Auto-refresh should work for CREATE/DROP/ALTER TABLE statements
- If not working, manually refresh: Press `R` in explorer or run `:EnhanceRefresh`
- Check `:messages` for errors

## vim-dadbod-ui Migration

If you're migrating from vim-dadbod-ui, enhance.nvim uses the same connection format!

### Shared Connections File

Point both plugins to the same file:

**vim-dadbod-ui:**
```lua
vim.g.db_ui_save_location = '~/.local/share/nvim/dadbod_ui'
-- Connections stored in: ~/.local/share/nvim/dadbod_ui/connections.json
```

**enhance.nvim:**
```lua
require("enhance").setup({
  connections_file = "~/.local/share/nvim/dadbod_ui/connections.json",
})
```

Now both plugins share the same connections! 🎉

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Running tests
- Code formatting standards
- Linting guidelines
- PR submission process
- Bug report template

## License

Apache 2.0 License

## Acknowledgments

- **vim-dadbod** and **vim-dadbod-ui** by @kristijanhusak for inspiration and connection format
- **Neovim community** for excellent plugin development resources

