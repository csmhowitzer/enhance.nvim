# JSON Field Handling Specification

**Version:** 1.1.0  
**Status:** Planning  
**Created:** 2025-12-28

## Overview

Add intelligent JSON field detection and expandable viewing to enhance.nvim result tables. When JSON data is detected in result cells, provide visual indicators and allow users to expand/view formatted JSON in a floating window.

## Goals

1. **Auto-detect JSON fields** in query results without performance impact
2. **Visual indicators** for cells containing JSON
3. **Expandable view** with pretty-printed, syntax-highlighted JSON
4. **Consistent UX** matching scratch-manager.nvim floating window style

## Non-Goals (Future Versions)

- Editing JSON inline
- JSON schema validation
- Deep JSON querying/filtering
- Multi-column JSON navigation (v2.0)

---

## Phase 1: Detection & Visual Indicator

### JSON Detection Strategy

**Performance-conscious approach:**
- Only check **first 3-5 rows** of results for JSON patterns
- Cache detection results per column
- Use quick pattern matching before full parsing

**Detection logic:**
```lua
-- For each column in first N rows:
1. Check if cell starts with `{` or `[`
2. Validate with json_utils.is_json()
3. Mark column as "json_column" if valid
4. Apply to all rows in that column
```

**Files:**
- `lua/enhance/json_utils.lua` ✅ (created)
- `lua/enhance/json_detector.lua` (new - detection logic)

### Visual Indicators

**In-table display:**
- Truncated JSON shows first 47 chars + `...` (existing behavior)
- Add subtle highlight to JSON cells: `EnhanceJsonCell`
- Highlight group: Light blue/cyan tint, italic

**Highlight definition:**
```lua
vim.api.nvim_set_hl(0, 'EnhanceJsonCell', {
  fg = '#74c7ec',  -- Cyan (scratch-manager title color)
  italic = true,
  default = true
})
```

**Files to modify:**
- `lua/enhance/init.lua` - Add highlight group
- `lua/enhance/results.lua` - Apply highlights to JSON cells

---

## Phase 2: Expandable View

### Keymap

**Options:**
- `gj` - "go to json" (vim-style, mnemonic)
- `<leader>dj` - "display json" (explicit, less conflict)

**Behavior:**
- Trigger when cursor is on a cell containing JSON
- Show error/notification if cell is not JSON
- Works in both formatted and raw result modes

### Floating Window

**Style:** Match scratch-manager.nvim floating window
- Centered on screen
- Border: rounded with cyan color (`#74c7ec`)
- Title: `" JSON View "` with green highlight (`#a6d189`)
- Footer: `" Press 'q' or <Esc> to close "` with cyan italic

**Window sizing:**
- Width: 80 columns (or 80% of screen width, whichever is smaller)
- Height: Auto-sized to content (max 40 lines, or 80% of screen height)
- Scrollable if content exceeds max height

**Content:**
- Pretty-printed JSON with 2-space indentation
- Syntax highlighting: `json` filetype
- Read-only buffer
- Line numbers enabled

**Reference implementation:**
- See `~/plugins/scratch-manager.nvim/lua/scratch-manager/ui.lua`
- Specifically `create_selection_window()` function

**Files:**
- `lua/enhance/json_viewer.lua` (new - floating window logic)
- `lua/enhance/results.lua` - Add keymap registration

---

## Phase 3: Integration

### Result Buffer Keymaps

**Add to `results.lua` keymap setup:**
```lua
-- JSON expansion keymaps
vim.keymap.set('n', 'gj', function()
  require('enhance.json_viewer').expand_json_at_cursor()
end, { buffer = bufnr, desc = 'Expand JSON field' })

vim.keymap.set('n', '<leader>dj', function()
  require('enhance.json_viewer').expand_json_at_cursor()
end, { buffer = bufnr, desc = 'Display JSON field' })
```

### Configuration

**Add to config.lua:**
```lua
---@class EnhanceConfig
---@field json JsonConfig JSON field handling configuration

---@class JsonConfig
---@field enabled boolean Enable JSON detection and expansion (default: true)
---@field auto_detect boolean Auto-detect JSON in results (default: true)
---@field detection_sample_size number Number of rows to sample for detection (default: 5)
---@field keymap_expand string Keymap to expand JSON (default: 'gj')
---@field keymap_expand_alt string Alternative keymap (default: '<leader>dj')
---@field highlight_cells boolean Highlight JSON cells in table (default: true)
```

---

## Implementation Plan

### Step 1: JSON Detection (Session 1)
- [x] Create `json_utils.lua` with detection functions
- [ ] Create `json_detector.lua` with column detection logic
- [ ] Add tests for JSON detection
- [ ] Integrate detection into result parsing

### Step 2: Visual Indicators (Session 1-2)
- [ ] Add `EnhanceJsonCell` highlight group
- [ ] Apply highlights to detected JSON cells
- [ ] Test with CustomerConfig table

### Step 3: Floating Window (Session 2)
- [ ] Create `json_viewer.lua` with floating window
- [ ] Implement pretty-print display
- [ ] Add syntax highlighting
- [ ] Reference scratch-manager.nvim patterns

### Step 4: Keymaps & Integration (Session 2-3)
- [ ] Add keymaps to result buffers
- [ ] Add configuration options
- [ ] Update README with JSON feature docs
- [ ] Add help documentation

### Step 5: Testing & Polish (Session 3)
- [ ] Write comprehensive tests
- [ ] Test with various JSON structures
- [ ] Test edge cases (malformed JSON, large JSON, nested arrays)
- [ ] Performance testing with large result sets

---

## Testing Strategy

**Test cases:**
1. Simple JSON objects `{"key": "value"}`
2. Nested objects `{"user": {"name": "John", "age": 30}}`
3. Arrays `["item1", "item2", "item3"]`
4. Mixed types `{"string": "text", "number": 42, "bool": true, "null": null}`
5. Large JSON (100+ lines)
6. Malformed JSON (should not detect)
7. NULL values (should not detect as JSON)
8. Empty strings (should not detect as JSON)

**Performance tests:**
- 1000+ row result set with JSON columns
- Multiple JSON columns in same table
- Very large JSON objects (10KB+)

---

## Future Enhancements (v2.0+)

- **Copy to clipboard:** `yj` to yank formatted JSON
- **Edit JSON:** Open in editable buffer, update cell on save
- **JSON path navigation:** Show JSON path of cursor position
- **Multi-column navigation:** Jump between JSON fields in same row
- **JSON diff:** Compare JSON between rows
- **Schema validation:** Validate against JSON schema

