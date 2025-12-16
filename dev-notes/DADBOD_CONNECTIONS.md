# Using vim-dadbod-ui Connections

**Date**: 2025-12-02  
**Agent**: ML (Mel)  
**Discovery**: User has existing connections in dadbod_ui

---

## Existing Connection Found

**File**: `~/.local/share/nvim/dadbod_ui/connections.json`

**Content**:
```json
[
  {
    "url": "sqlite:/Users/wwmac/documents/projects/examples/example.db",
    "name": "example.db"
  }
]
```

**Database**: `/Users/wwmac/documents/projects/examples/example.db` (256KB)

---

## Database Schema

The database contains **32 tables** including:

**Core Tables**:
- Applications, ApplicationEnvironments, ApplicationLogins, ApplicationProjects
- BusinessUnits, BusinessUnitBudgets, BusinessUnitExpenses
- Departments, DepartmentBusinessUnit, DepartmentEmployees
- Employees, EmployeeRoles, EmployeeSalaries, DirectReports
- Teams, TeamMembers
- Projects, Releases
- Tasks, TaskAssignments, TaskStatus
- FeatureRequests, FeatureRequestTypes, FeatureRequestStatus, FeatureRequestStatusHistory
- Roles, Priorities, Requesters, Comments
- Environments, PayrollTransactions

This is a comprehensive business/project management database!

---

## Updated Configuration

Use the **real database** instead of test database:

```lua
{
  dir = "~/plugins/enhance.nvim",
  name = "enhance",
  config = function()
    require("enhance").setup({
      enabled = true,
      connections = {
        {
          name = "example.db",
          type = "sqlite",
          path = "/Users/wwmac/documents/projects/examples/example.db",
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

## Sample Queries for Testing

### List All Tables
```sql
SELECT name, type 
FROM sqlite_master 
WHERE type IN ('table', 'view') 
ORDER BY name;
```

### Explore Employees
```sql
SELECT * FROM Employees LIMIT 10;
```

### Explore Projects
```sql
SELECT * FROM Projects LIMIT 10;
```

### Explore Tasks
```sql
SELECT * FROM Tasks LIMIT 10;
```

### Join Example
```sql
SELECT 
  e.name as employee,
  d.name as department
FROM Employees e
LEFT JOIN DepartmentEmployees de ON e.id = de.employee_id
LEFT JOIN Departments d ON de.department_id = d.id
LIMIT 10;
```

---

## Future Enhancement: Import from dadbod_ui

We could add a feature to automatically import connections from dadbod_ui:

```lua
-- Future feature
local function import_dadbod_connections()
  local connections_file = vim.fn.expand("~/.local/share/nvim/dadbod_ui/connections.json")
  if vim.fn.filereadable(connections_file) == 1 then
    local content = vim.fn.readfile(connections_file)
    local json = vim.fn.json_decode(table.concat(content, "\n"))
    
    local connections = {}
    for _, conn in ipairs(json) do
      -- Parse URL: "sqlite:/path/to/db"
      local db_type, path = conn.url:match("^(%w+):(.+)$")
      table.insert(connections, {
        name = conn.name,
        type = db_type,
        path = path,
      })
    end
    
    return connections
  end
  return {}
end
```

**Priority**: Low (manual config works fine for MVP)

---

## Test Database Still Available

The test database I created is still available if needed:
- **Path**: `~/.local/share/nvim/enhance/test.db`
- **Tables**: users, products
- **Use case**: Simple testing without touching real data


