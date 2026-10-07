<img width="576" height="384" alt="image" src="https://github.com/user-attachments/assets/c9771bd0-8f83-4533-8d29-104db5b8ddce" />


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

| Database | CLI Tool |
|----------|----------|
| **SQLite** | `sqlite3` |
| **SQL Server** | `sqlcmd` |
| **MySQL** | `mysql` |
| **PostgreSQL** | `psql` |

**SQLite** — macOS:

```sh
brew install sqlite3
```

Linux:

```sh
apt install sqlite3
```

**SQL Server** — macOS:

```sh
brew install sqlcmd
```

For Windows or Linux, see [Microsoft's sqlcmd installation guide](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility).

**MySQL** — macOS:

```sh
brew install mysql-client
```

Linux:

```sh
apt install mysql-client
```

**PostgreSQL** — macOS:

```sh
brew install postgresql
```

Linux:

```sh
apt install postgresql-client
```

Install only the tools for databases you use.

Run `:checkhealth enhance` to verify CLI tools and *vim-dadbod* are installed

### Docker Connections

When connecting to databases running in Docker containers, note the following:

**MySQL:** Use `127.0.0.1` instead of `localhost` to avoid socket errors:

```json
{
  "name": "Docker MySQL",
  "url": "mysql://root:root@127.0.0.1:3306/example_mysql"
}
```

**Why:** The MySQL client uses Unix sockets when connecting to `localhost`, but Docker containers don't expose socket files on the host system. Using `127.0.0.1` forces a TCP connection.

**All databases:** Ensure CLI tools are installed on your host system (see table above). enhance.nvim runs database commands from the host, not inside containers, so the CLI tools must be available in your system PATH.

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
| `ui.dashboard.card_border` | string | `"EnhanceDashboardBorder"` | Highlight group for database dashboard card borders (defaults to purple `#cba6f7`) |
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
| `:EnhanceStart` | Open the explorer and welcome page (preserves an existing file) |
| `:EnhanceStop` | Stop enhance workspace and close all windows |
| `:EnhanceExplorer` | Toggle database explorer drawer |
| `:EnhanceResults` | Toggle results window |
| `:EnhanceQuery` | Create new query buffer |
| `:EnhanceRefresh` | Refresh explorer (clear cache and redraw) |
| `:EnhanceDeleteFile [filename]` | Delete file (current buffer or specified) |
| `:EnhanceToggle` | Toggle plugin enabled/disabled |

### Workflow

1. **Start**: Press `<leader>de` or run `:EnhanceStart` to open the explorer and welcome page in an empty window
2. **Connect**: Press `<CR>` on a connection in explorer to test and expand it; the welcome page is removed and a database overview appears
3. **New Query**: Press `o` on "New Query" or run `:EnhanceQuery`
4. **Write**: Write your SQL query in the editor
5. **Execute**: Press `<F5>` to execute (normal mode: entire buffer, visual mode: selection)
6. **View**: Results appear in bottom window with status line
7. **Save**: Use `:w` to save query (prompts for filename)
8. **Manage**: Use explorer to view buffers, saved queries, and tables

The welcome page offers `e` to focus the explorer, `n` for a new query after connecting,
and `?` for help. The connected dashboard spells the database name in its top
banner (wrapping long names) and keeps these actions beneath it. It shows
table/view counts, saved query files, persisted temp query files, table names,
and connection details. Unsaved in-memory temp buffers are not included in the
on-disk count. **DATABASE METADATA** groups the overview cards. Database card
borders and section headings are purple, card titles and labels are blue, and
chart descriptions use the subtitle's muted italic style. Views are shown as
unavailable for databases without explorer
view support. For SQL Server, a seventh overview card shows **Database Data Size**:
space used across all database data files (excluding transaction logs), in kB,
MB, or GB. It loads in the background and shows `Unavailable` if the lookup
fails. The welcome page is temporary; the dashboard stays hidden when
you open a query and can be reopened from **Dashboard** under its connection
in the explorer (`<CR>` or `o`). It returns in the editor pane, not a separate
Neovim tab.

For SQL Server, a rows-per-table chart loads the eight largest user tables in
the background. Counts are **catalog estimates**, not exact `COUNT(*)` results;
the chart reports unavailable metadata if the catalog query cannot run. Press
`r` on the dashboard to refresh that connection's object counts, data size, and chart.
Chart rows have breathing room between bars. The **Pinned Tables** card sits
beside Top 8 when the editor pane is wide enough, stacking below it when narrow.
It holds up to eight tables per connection in alphabetical order. Pin a table in the
explorer with `<leader>dp` on its row or choose **Pin to dashboard** under the
expanded table; the action becomes **Unpin from dashboard** once pinned. A yellow
pin appears beside pinned tables. Pins persist in
`stdpath('data')/enhance.nvim/<connection name>/pins.json`. SQL Server shows
catalog row estimates as bars scaled to the largest pinned table, with a blank
line between pins; other engines show table names.
When SQL Server tables are pinned, three more cards appear below the charts:
**Columns**, **Indexes**, and **Data Size**. Each lists every pinned table in
alphabetical order. Index counts include primary-key indexes but exclude the
heap; data size uses allocated heap/clustered and LOB pages (excluding
nonclustered index pages), displayed in kB, MB, or GB. Metadata loads in the
background; missing tables show `N/A`. All three cards disappear when there
are no pins. Scroll the dashboard normally to see cards below the window.

### SQL Server table dashboards

Expand any SQL Server table in the explorer and select **Dashboard** to see its
own overview in the editor pane. Under **TABLE METADATA**, four cards show its
estimated row count, non-heap index count, column count, and allocated table
data size; their descriptions use the same muted italic styling as the dashboard
subtitle. A full-width **CREATE TABLE** card displays a syntax-highlighted
generated script from the catalog (columns, identity, defaults, and primary
key); it is a convenient schema preview, not a complete migration script for
every SQL Server table feature. Its centered,
italic `yc copy` action copies the complete generated script to the system
clipboard. The **REFERENCES** section lists views, stored procedures, and
functions found in SQL Server's static dependency catalog, plus saved `.sql`
queries whose text mentions the table.
Dynamic SQL dependencies may not be recorded by the catalog. The references
card uses the same type icons as the explorer, with one name per row and a
centered selection hint. Move through the list with `j`/`k` and press `<CR>` to
open a saved query or the
object's definition in the editor. The selected reference highlights when the
cursor reaches it. Press `r` to refresh the table's data. The table dashboard
remains available after opening a reference; select its explorer Dashboard
action to return. Table cards have green borders, blue labels, and purple
section headings. Cards stack when the editor pane is narrow.

To customize the database dashboard card border, set a highlight group in setup:

```lua
require('enhance').setup({ ui = { dashboard = { card_border = 'MyDashboardBorder' } } })
vim.api.nvim_set_hl(0, 'MyDashboardBorder', { fg = '#cba6f7' })
```

### SQL completion

When an Enhance query buffer is connected to SQL Server, it supplies the active
database to `vim-dadbod-completion`. With `blink.cmp` configured to use the
`vim_dadbod_completion.blink` provider for SQL buffers, typing suggests tables,
columns (including aliases), and SQL keywords. The connection stays local to
each query buffer, so switching queries uses the right database. You can also
request Dadbod's built-in completion with `Ctrl-x Ctrl-o` in insert mode.

For `blink.cmp`, add the SQL source to your configuration:

```lua
sources = {
  per_filetype = { sql = { inherit_defaults = true, 'dadbod' } },
  providers = { dadbod = { name = 'Dadbod', module = 'vim_dadbod_completion.blink' } },
}
```

### Keymaps

**Explorer:**
- `<CR>` - Expand/collapse nodes (connections, folders, tables, buffers with results)
- `o` - Open buffer, saved query, or create new query/script
- `q` - Close explorer
- `<leader>de` - Toggle explorer
- `<leader>dp` - Pin/unpin the table under the explorer cursor (maximum eight per connection)
- `R` - Refresh explorer (clear cache and redraw)
- `dd` or `D` - Delete file under cursor
- `d` or `D` (visual) - Delete selected files
- `r` - Rename saved query (prompts for new name)

**Query Buffer:**
- `<F5>` - Execute query (normal mode: entire buffer, visual mode: selection)
- `:w` - Save query (prompts for filename if new)

**Results Buffer:**
- `q` - Close results window
- `:w` - Save associated query buffer (smart redirect)
- `yc` - Copy full cell under cursor (even if its display is truncated)
- `yr` - Copy full row as tab-separated values (without display truncation)
- `ys` - Copy the current result set as tab-separated text, including `#` row numbers and headers
- `gk` - Show any data cell, truncated or not, in a scrollable popup; detected JSON opens the JSON viewer (`q` or `Esc` closes either)
- `<leader>dh` - Toggle SQL Server datatype labels below result headers (works from any buffer)
- `Alt-k` / `Alt-j` - Previous / next result set (wraps at either end)
- `Alt-h` / `Alt-l` - Previous / next column within the current data row (wraps within the row)
- `h` / `j` / `k` / `l` - Native cursor movement
- `Ctrl-d` / `Ctrl-u` - Scroll the results window

**JSON Viewer** (open a JSON result cell with `gj` or `<leader>dj`):
- `Alt-j` / `Alt-k` - Next / previous JSON row
- `Alt-h` / `Alt-l` - Previous / next JSON column
- `Ctrl-n` / `Ctrl-p` and `Ctrl-h` / `Ctrl-l` - Existing row and column navigation
- `q` / `Esc` - Close the viewer

The JSON viewer title includes the column name and SQL datatype when known,
and updates as you navigate rows or JSON columns.

These normal-mode mappings are local to results buffers. Copy mappings write to
Neovim's unnamed register for `p` and the system clipboard for Cmd-V. Place the
cursor on a data row for `yc` or `yr` (`yc` requires a cell); `ys` works anywhere
inside a result set, including its header or an empty table. `Alt-j/k` wrap
between the last and first result sets. `Alt-h/l` wrap from the first/last
column to the other end of the same row; `Alt-l` enters the first data row
from the status line. `gk` shows the full value even if its table display is
truncated. Its title is the column header and, when known, SQL data type;
its border matches the cell's result color when one is assigned. On a JSON
cell, `gk` opens the syntax-highlighted JSON viewer instead.
The non-JSON cell popup has padding around short values. `<leader>dh` adds a
color-matched datatype row between each SQL Server table's column names and
separator, including empty tables when type metadata is available. It starts
hidden and toggles across open results without changing copied data.
SQL Server's `sqlcmd` may limit values longer than 4,096 characters before
Enhance receives them; copying preserves the full value returned by `sqlcmd`.

SQL Server result cells with numeric types use `EnhanceNumberCell` (peach);
date/time types use `EnhanceDateCell` (mauve). Colors follow the SQL result
column's actual type, so numeric- or date-looking text in `varchar`/`nvarchar`
columns stays plain. NULL and detected JSON cells retain their separate
highlights. When SQL Server cannot describe a query's result types (for example,
one using a local temporary table), Enhance displays its values without type
colors. The type lookup runs as an additional `sqlcmd` query for each result set.

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

**Multiple SELECT Statements** (batched execution with result set headers):
```
Statements: 2 | Rows: 7 | 15.43ms | example.db | sqlite | 2025-12-17 22:04:38
─────────────────────────────────────────────────────────────────────────────
Result Set 1/2 | Rows: 5

id  name       email
--  ---------  ------------------
1   John Doe   john@example.com
2   Jane Doe   jane@example.com

Result Set 2/2 | Rows: 2

count
-----
5
```

## Database-Specific Features

### SQL Server

enhance.nvim provides **full SSMS parity** for SQL Server with advanced features:

- **Stop-on-Error Execution**: DML/DDL statements execute individually and stop on first error
- **Individual Statement Timing**: Each DML/DDL statement shows its own execution time
- **Batch Mode for SELECT**: Multiple SELECT statements execute together for performance
- **Smart Error Detection**: Detects errors even when `sqlcmd` exit code is 0
- **Data-Driven Highlighting**: Error messages highlighted in red automatically
- **Row Count Extraction**: Shows affected rows for INSERT/UPDATE/DELETE operations

**Example - Multiple DML Statements:**
```sql
UPDATE Users SET status = 'active' WHERE id = 1;
DELETE FROM Sessions WHERE expired = 1;
INSERT INTO AuditLog (action, timestamp) VALUES ('cleanup', GETDATE());
```

**Output:**
```
Statements: 3 | Rows: 15 | 45.23ms | ProductionDB | sqlserver | 2025-12-17 22:04:38
────────────────────────────────────────────────────────────────────────────────────
✓ Updated 1 row | 12.34ms

✓ Deleted 10 rows | 18.45ms

✓ Inserted 1 row | 14.44ms
```

### SQLite, MySQL, PostgreSQL

All databases support:
- Multiple SELECT statement batching with result set headers
- DML/DDL success messages with row counts
- Error detection and highlighting
- Auto-refresh on DDL operations

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
vim.api.nvim_set_hl(0, 'EnhanceError', { fg = '#f38ba8', bold = true }) -- Red (error messages)
vim.api.nvim_set_hl(0, 'EnhanceNumberCell', { fg = '#fab387' })       -- SQL Server numeric values
vim.api.nvim_set_hl(0, 'EnhanceDateCell', { fg = '#cba6f7' })         -- SQL Server date/time values
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

Create the connections file:

```sh
mkdir -p ~/.local/share/enhance
cat > ~/.local/share/enhance/connections.json << 'EOF'
[
  {
    "name": "My App DB",
    "url": "sqlite:/Users/yourusername/myapp.db"
  }
]
EOF
```

Configure the plugin in your Neovim config:

```lua
require("enhance").setup({
  enabled = true,
})
```

Run `:EnhanceStart`, expand the connection with `<CR>`, then press `o` on
"New Query". Enter a query such as:

```sql
SELECT * FROM users WHERE active = 1;
```

Press `<F5>` to execute, then `:w` to save it as `active_users`.

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
1. Verify the connections file exists:

   ```sh
   cat ~/.local/share/enhance/connections.json
   ```

2. Check JSON syntax is valid (use `jq` or online validator)
3. Run `:messages` to see error details
4. Verify file path in config matches actual file location

### Query execution fails

**Problem**: Query executes but shows no results or errors

**Solution**:
1. Check `:checkhealth enhance` for connection issues
2. Verify the database file exists (for SQLite):

   ```sh
   ls -la /path/to/db.db
   ```

3. Test the connection manually using the appropriate CLI tool:

   **SQLite:**

   ```sh
   sqlite3 /path/to/db.db "SELECT 1;"
   ```

   **SQL Server:**

   ```sh
   sqlcmd -S server -d database -U user -P password -Q "SELECT 1;"
   ```

   **MySQL:**

   ```sh
   mysql -h host -u user -ppassword database -e "SELECT 1;"
   ```

   **PostgreSQL:**

   ```sh
   psql "host=host dbname=database user=user password=password" -c "SELECT 1;"
   ```
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
