# enhance.nvim Roadmap

## For v1.0.0 (Stable Release)

### Beta Feedback
- Bug fixes from beta testing
- Performance improvements
- Documentation refinements

### Polish
- Edge case handling
- Error message improvements
- UX refinements

## v1.1.0

### Database Parity
- MySQL debatching and error handling (apply SQL Server patterns)
- PostgreSQL debatching and error handling (apply SQL Server patterns)
- SQLite regression testing (verify no regressions from SQL Server work)

### Enhanced Results
- **Truncated column viewing** - Expandable view for long text/JSON columns
  - Horizontal scrolling or column width adjustment
  - Popup/floating window for full content
  - Smart truncation with visual indicators
- JSON field handling with expandable view
- Adjustable column widths
- Column sorting
- Result filtering

## Future Considerations

### Query Notebook Feature
- Cell-based query execution
- Inline results display
- Markdown documentation support
- Query parameters and variables
- Notebook file persistence

### Advanced Features
- **Temp table persistence** - Session management for temp tables
  - Investigation: Test behavior across all 4 database types
  - Determine if connection pooling/session management needed
  - Define expected user behavior (SSMS-like persistence vs. fresh connections)
  - Implement solution based on findings
- **Stored procedure support** - Execute sprocs with parameters
  - Handle multiple result sets from stored procedures
  - Display output parameters and return values
  - Support for all 4 database types
  - Parameter input UI (prompt or form)
- Query templates
- Transaction management
- Multi-connection queries

### Performance
- Large result set optimization
- Lazy loading for explorer
- Query result caching

### Integration
- Snippet support

## v2.0 (and future support)

### NoSQL Database Support
- Redis / **MongoDB**
  - JSON query input (e.g., `db.users.find({ age: { $gt: 25 } })`)
  - Pretty-printed JSON document output
  - Collection browser (not table-based)
  - Document viewer with syntax highlighting
  - Basic `find()` queries only
  - No aggregation pipelines initially
