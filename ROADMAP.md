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

### Enhanced Results
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
- Query templates
- Stored procedure support
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
