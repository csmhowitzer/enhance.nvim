# Contributing to enhance.nvim

Thank you for your interest in contributing to enhance.nvim! We appreciate your help in making this database UI plugin better for the Neovim community.

## 🧪 Running Tests

enhance.nvim uses [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for testing with the Plenary Busted framework.

### Prerequisites

Install plenary.nvim:

```lua
-- In your lazy.nvim config
{
  "nvim-lua/plenary.nvim",
}
```

### Running the Test Suite

Run all tests:

```vim
:PlenaryBustedDirectory tests
```

Run individual test files:

```vim
:PlenaryBustedFile tests/config_spec.lua
:PlenaryBustedFile tests/connections_spec.lua
:PlenaryBustedFile tests/init_spec.lua
:PlenaryBustedFile tests/explorer_spec.lua
:PlenaryBustedFile tests/query_spec.lua
:PlenaryBustedFile tests/executor_spec.lua
:PlenaryBustedFile tests/results_spec.lua
```

Run tests from command line:

```bash
# Run all tests
nvim --headless -c "PlenaryBustedDirectory tests" -c "qa!" > test_output.log 2>&1

# Run specific test file
nvim --headless -c "PlenaryBustedFile tests/config_spec.lua" -c "qa!" > test_output.log 2>&1

# View results
cat test_output.log
```

### Test Coverage

The test suite includes 67 tests covering:
- Configuration validation and merging
- Connection management
- Plugin initialization and commands
- Explorer tree building and icon handling
- Query execution logic
- Database-specific executor routing
- Results display and formatting

### Writing Tests

When adding new functionality:

1. **Expose internal functions** for testing using the `M._function_name` pattern:
   ```lua
   -- At end of module
   M._validate_config = validate_config
   M._build_tree = build_tree
   ```

2. **Test behavior, not implementation** - Focus on what the user expects
3. **Use descriptive test names** - `it("should normalize database type names")`
4. **Test edge cases** - Empty inputs, invalid data, boundary conditions
5. **Keep tests focused** - One concept per test

## 🎨 Formatting

enhance.nvim follows standard Lua formatting conventions:

- **Indentation**: 2 spaces (no tabs)
- **Line length**: 100 characters maximum (prefer 80)
- **Strings**: Double quotes for user-facing strings, single quotes for internal
- **Tables**: Trailing commas for multi-line tables
- **Functions**: Local functions before module functions

### Example:

```lua
local function validate_connection(conn)
  if not conn.name or conn.name == "" then
    return false, "Connection name is required"
  end
  return true
end

function M.setup(opts)
  local config = vim.tbl_deep_extend("force", defaults, opts or {})
  return config
end
```

## 🔍 Linting

### Lua Annotations

All public functions should have complete Lua annotations for LSP support:

```lua
---Configure enhance.nvim with the provided options
---@param opts table? Configuration options
---  - enabled (boolean): Enable/disable plugin
---  - connections (table[]): Database connections
---@return table config The merged configuration
function M.setup(opts)
  -- implementation
end
```

### Type Definitions

Use `@class` for complex types:

```lua
---@class Connection
---@field name string Connection display name
---@field type string Database type (sqlite, sqlserver, mysql, postgres)
---@field path string? SQLite database file path
---@field host string? Database server host
---@field port number? Database server port
---@field database string? Database name
---@field user string? Database user
---@field password string? Database password
```

### Health Check

Run the health check to verify your changes:

```vim
:checkhealth enhance
```

The health check validates:
- Plugin loaded correctly
- Database CLI tools available
- Connections configured properly
- Commands registered
- Core functionality working

## 🌿 Getting a Branch Ready for a PR

1. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes** following the coding standards above

3. **Add tests** for new functionality
   - All new features must have tests
   - Bug fixes should include regression tests

4. **Run the test suite** and ensure all tests pass:
   ```vim
   :PlenaryBustedDirectory tests
   ```

5. **Update documentation**:
   - Update `README.md` if adding user-facing features
   - Update `doc/enhance.txt` help documentation
   - Add Lua annotations to new functions
   - Update health check if adding new dependencies

6. **Commit your changes** with clear, descriptive messages:
   ```bash
   git commit -m "feat: add support for MongoDB connections"
   git commit -m "fix: handle empty query buffer execution"
   git commit -m "docs: update README with new keymaps"
   ```

7. **Rebase on latest main** before submitting:
   ```bash
   git fetch origin
   git rebase origin/main
   ```

## 📬 Opening a Pull Request

1. **Push your branch** to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

2. **Open a Pull Request** on GitHub with:
   - **Clear title** describing the change
   - **Description** explaining:
     - What problem does this solve?
     - How does it solve it?
     - Any breaking changes?
     - Screenshots/demos if UI changes
   - **Link to related issues** if applicable

3. **PR Checklist**:
   - [ ] All tests pass (`:PlenaryBustedDirectory tests`)
   - [ ] New tests added for new functionality
   - [ ] Documentation updated (README, help docs)
   - [ ] Lua annotations added to new functions
   - [ ] Health check updated if needed
   - [ ] No breaking changes (or clearly documented)
   - [ ] Commit messages are clear and descriptive

4. **Respond to feedback**:
   - Address review comments promptly
   - Push additional commits to the same branch
   - Mark conversations as resolved when addressed

### PR Title Format

Use conventional commit format:

- `feat: add PostgreSQL connection pooling`
- `fix: handle empty query buffer execution`
- `docs: update README with new examples`
- `test: add tests for connection validation`
- `refactor: simplify executor routing logic`
- `perf: optimize tree building performance`

## 🐛 Bug Submissions

### Before Submitting

1. **Check existing issues** - Your bug may already be reported
2. **Verify it's a bug** - Test with minimal config
3. **Check health** - Run `:checkhealth enhance`
4. **Test with latest version** - Update to latest main branch

### Bug Report Template

When submitting a bug, include:

**Description**
A clear description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Configure enhance.nvim with '...'
2. Run command '...'
3. Execute query '...'
4. See error

**Expected Behavior**
What you expected to happen.

**Actual Behavior**
What actually happened.

**Environment**
- Neovim version: (`:version`)
- enhance.nvim version: (commit hash or tag)
- OS: (macOS, Linux, Windows WSL2)
- Database type: (SQLite, SQL Server, MySQL, PostgreSQL)
- Database CLI tool version: (`sqlite3 --version`, `sqlcmd -?`, etc.)

**Health Check Output**
```
:checkhealth enhance
(paste output here)
```

**Minimal Config**
Provide a minimal `init.lua` that reproduces the issue:

```lua
-- minimal_init.lua
vim.cmd([[set runtimepath=$VIMRUNTIME]])
vim.cmd([[set packpath=/tmp/nvim/site]])

local package_root = "/tmp/nvim/site/pack"
local install_path = package_root .. "/packer/start/packer.nvim"

local function load_plugins()
  require("packer").startup({
    {
      "wbthomason/packer.nvim",
      {
        "yourusername/enhance.nvim",
        config = function()
          require("enhance").setup({
            connections = {
              { name = "Test", type = "sqlite", path = "/tmp/test.db" }
            }
          })
        end,
      },
    },
  })
end

load_plugins()
```

**Additional Context**
Any other context about the problem (screenshots, error messages, etc.)

### Feature Requests

For feature requests, include:

1. **Use case** - What problem does this solve?
2. **Proposed solution** - How should it work?
3. **Alternatives** - What other solutions did you consider?
4. **Examples** - How do other tools handle this?

---

## 📚 Additional Resources

- **Help Documentation**: `:help enhance`
- **Health Check**: `:checkhealth enhance`
- **Test Suite**: `tests/` directory
- **Code Patterns**: Follow existing module structure in `lua/enhance/`

## 🙏 Thank You

Your contributions make enhance.nvim better for everyone. We appreciate your time and effort!


