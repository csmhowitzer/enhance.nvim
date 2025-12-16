# enhance.nvim

Database UI enhancement for Neovim. A pure Lua database interface with intelligent result formatting and modern UI.

This tool is aimed at providing a great stepping stone into a Neovim based database tool. Hopefully you'll find it 
provides helpful features. At a minimum you will see that it delivers the familiar keymaps while in the plugins that
you'd expect while in any other editor inside Neovim. It supports **MySql**,**Postgres**, **Sqlite**, and 
**SQL Server** out of the box. 

Enjoy!

## Features

- **Multi-database**: SQL Server, SQLite, MySQL, PostgreSQL
- **Fast execution**: With less to load like traditional apps!
- **Explorer UI**: Tree-based database browser with drawer layout
- **Temp Buffers**: Temp buffers are stored without needing to save.
- **Configurable**: Customizable keymaps and UI preferences

## Installation

### With lazy.nvim

```lua
-- In your lua/plugins/enhance.lua or similar
return {
  {
    "csmhowitzer/enhance.nvim",  -- or dir = "~/plugins/enhance.nvim" for local
    config = function()
      require("enhance").setup({
        enabled = true,
        connections = {
          {
            name = "Production DB",
            type = "sqlserver",
            host = "localhost",
            database = "MyDatabase",
            user = "sa",
            password = "YourPassword",
          },
          {
            name = "Local SQLite",
            type = "sqlite",
            path = "~/myapp.db",
          }
        },
      })
    end,
  },
}
```

## Configuration

### Basic Setup

```lua
require("enhance").setup({
  enabled = true,
  connections = {
    -- Add your database connections here
  },
})
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable/disable the plugin |
| `connections` | table[] | `{}` | List of database connections (see below) |

### Connection Configuration

#### SQL Server (Primary)

```lua
{
  name = "Production DB",
  type = "sqlserver",  -- or "sql server", "mssql"
  host = "localhost",
  database = "MyDatabase",
  user = "sa",
  password = "YourPassword",
}
```

#### SQLite

```lua
{
  name = "Local DB",
  type = "sqlite",
  path = "~/path/to/database.db",
}
```

#### MySQL

```lua
{
  name = "MySQL DB",
  type = "mysql",  -- or "mariadb"
  host = "localhost",
  port = 3306,
  database = "mydb",
  user = "root",
  password = "secret",
}
```

#### PostgreSQL

```lua
{
  name = "Postgres DB",
  type = "postgres",  -- or "postgresql"
  host = "localhost",
  port = 5432,
  database = "mydb",
  user = "postgres",
  password = "secret",
}
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:EnhanceStart` | Start enhance workspace with explorer and query editor |
| `:EnhanceStop` | Stop enhance workspace and close all windows |
| `:EnhanceExplorer` | Toggle database explorer drawer |
| `:EnhanceResults` | Toggle results window |
| `:EnhanceQuery` | Create new query buffer |
| `:EnhanceDeleteFile [filename]` | Delete file (current buffer or specified) |
| `:EnhanceToggle` | Toggle plugin enabled/disabled |

### Workflow

1. **Start**: Run `:EnhanceStart` to open workspace with explorer drawer
2. **Connect**: Press `<CR>` on a connection in explorer to expand it
3. **New Query**: Press `<CR>` on "New Query" or run `:EnhanceQuery`
4. **Write**: Write your SQL query in the editor
5. **Execute**: Press `<F5>` to execute (normal mode: entire buffer, visual mode: selection)
6. **View**: Results appear in bottom window
7. **Save**: Use `:w` to save query (prompts for filename)
8. **Manage**: Use explorer to view buffers, saved queries, and tables

### Keymaps

**Explorer:**
- `<CR>` - Expand/collapse connection or open item
- `q` - Close explorer
- `<leader>de` - Toggle explorer
- `dd` or `D` - Delete file under cursor
- `d` or `D` (visual) - Delete selected files

**Query Buffer:**
- `<F5>` - Execute query (normal mode: entire buffer, visual mode: selection)
- `:w` - Save query (prompts for filename if new)

**Results Buffer:**
- `q` - Close results window

## Examples

### Basic SQLite Workflow

```lua
-- 1. Configure connection
require("enhance").setup({
  connections = {
    { name = "My App DB", type = "sqlite", path = "~/myapp.db" }
  }
})

-- 2. Start workspace
:EnhanceStart

-- 3. Expand connection in explorer (press <CR>)
-- 4. Create new query (press <CR> on "New Query")
-- 5. Write query:
SELECT * FROM users WHERE active = 1;

-- 6. Execute (press <F5>)
-- 7. Save query (press :w, enter filename "active_users")
```

### SQL Server Connection

```lua
{
  name = "Production DB",
  type = "sqlserver",
  host = "localhost",
  database = "MyDatabase",
  user = "sa",
  password = "YourPassword",
}
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

**Solution**: Install required tools:
- SQLite: `brew install sqlite3` (macOS) or `apt install sqlite3` (Linux)
- SQL Server: `brew install sqlcmd` (macOS) or install from Microsoft
- MySQL: `brew install mysql-client` (macOS) or `apt install mysql-client` (Linux)
- PostgreSQL: `brew install postgresql` (macOS) or `apt install postgresql-client` (Linux)

### Query execution fails

**Problem**: Query executes but shows no results or errors

**Solution**:
1. Check `:checkhealth enhance` for connection issues
2. Verify database file exists (for SQLite)
3. Test connection manually: `sqlite3 /path/to/db.db "SELECT 1;"`
4. Check query syntax in database-specific tool first

### Explorer not showing buffers

**Problem**: Buffers section shows (0) even with open query buffers

**Solution**: Buffers are only tracked after executing a query. Execute a query first, then the buffer will appear in the explorer.

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Running tests
- Code formatting standards
- Linting guidelines
- PR submission process
- Bug report template

