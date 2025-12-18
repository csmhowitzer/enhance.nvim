# enhance.nvim Roadmap

## Current Status: Pre-Beta (v1.0.0-beta.1)

---

## 🎯 Beta Release Blockers

### ✅ ALL COMPLETE - READY FOR v1.0.0-beta.1!

1. ✅ **Tables List Not Refreshing** - Auto-refresh on DDL + manual refresh (`R` or `:EnhanceRefresh`)
2. ✅ **Security: Connection Info in Config** - vim-dadbod-ui format with external JSON file
3. ✅ **Visual Selection Execution** - Character-level selection with `<F5>` in visual mode
4. ✅ **DDL Statement Feedback** - Success messages for CREATE/DROP/ALTER TABLE
5. ✅ **README Updates** - Complete documentation with all features, examples, and troubleshooting

---

## 🚀 Post-Beta Features

### Notebook / Query Workflow Feature

**Description:** A notebook-style interface for database queries, allowing users to create reusable query workflows with multiple executable sections.

**Status:** Planning phase - design questions to be answered

**Design Questions to Address:**
1. **Cell-based execution?** - Each query is a "cell" that can be executed independently?
2. **Inline results?** - Results appear directly below the query (not in separate window)?
3. **Markdown support?** - Mix SQL with markdown documentation?
4. **Execution order?** - Run all cells in sequence, or just current cell?
5. **Persistence?** - Save notebooks as files (`.sql-notebook` or similar)?
6. **Variables/parameters?** - Pass results from one query to another?

**Reference Tools:**
- Azure Data Studio notebooks
- Jupyter notebooks (SQL kernels)
- DataGrip scratch files
- Observable notebooks

**Next Steps:**
- Answer design questions
- Create feature specification
- Design UI/UX
- Implementation plan

---

## 📋 Future Enhancements

### JSON Field Handling
- Special rendering for JSON columns
- Expandable/collapsible JSON view
- Syntax highlighting for JSON data

### Adjustable Column Widths
- Interactive column resizing in results
- Save column width preferences per table

### Query History
- Track executed queries
- Quick re-run from history
- Search query history

### Export Results
- Export to CSV, JSON, Excel
- Copy results to clipboard
- Save results to file

---

## 🎨 UI/UX Improvements

### Explorer Enhancements
- Auto-refresh after DDL statements
- Manual refresh command
- Search/filter tables
- Show table row counts

### Results Window
- Pagination for large result sets
- Sorting by column
- Filtering results
- Copy cell/row/column

---

## 🔧 Technical Debt

### Testing
- Add comprehensive test suite
- Integration tests for each database type
- Mock database connections for CI/CD

### Documentation
- Complete API documentation
- User guide with examples
- Video tutorials

### Performance
- Optimize large result set handling
- Lazy loading for explorer tree
- Query result caching

---

*Last Updated: 2025-12-17*

