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
- A notebook/journal is an ordered sequence of queries in an editable, Markdown-like file recognized by Enhance
- Execute each query manually, or automatically run the next query after the previous one completes
- Optionally use a previous query's output as input to a later query
- Inline results display
- Markdown documentation support
- Query parameters and variables
- Notebook file persistence

### Database Landing Dashboard
- Visual direction: SQL Studio-style overview in the editor pane beside Enhance's explorer — connection/database heading, compact metric cards, chart panels, and a metadata panel; adapt to terminal width and Neovim highlight groups rather than copying browser chrome
- Candidate cards: tables, views, indexes, triggers (only show supported, real catalog values for each database)
- Candidate charts: top tables by row count and indexes/columns per table; label estimates clearly and never run unbounded exact counts on startup
- Candidate metadata: database size, engine/version, and available creation/modified timestamps; omit fields the database cannot supply reliably
- Show the landing page when Enhance opens with a connected database; update it when the active connection changes
- Add a `Dashboard` entry under each database connection in the explorer so users can reopen that database's dashboard
- Provide a visible manual Refresh action/keymap; refresh only the selected database's metrics, including data changed outside Enhance
- After successful queries in the current instance, update local query-history charts immediately; invalidate affected database metrics on writes (INSERT/UPDATE/DELETE) and schema changes (CREATE/DROP/ALTER) so Refresh shows new data
- Offer configurable automatic refresh after writes, with inexpensive metadata updates only; defer expensive row counts to explicit refresh or opt-in sampling
- Proof of concept: connection/database name, database type, and table count (reuse explorer's cached table list)
- Small chart: last 10 query runtimes as bars, using locally collected execution history; show an empty state before any queries run
- Optional catalog chart: tables per schema, loaded in the background where the database exposes schemas (SQLite can show its main database as one group)
- Later: top tables by approximate record count where catalog statistics support it; make exact `COUNT(*)` sampling explicit and bounded, not part of opening the page
- Keep initial rendering fast: display cached/local metrics immediately, load optional metadata asynchronously, and avoid scanning table data on open
- Use Typr's in-Neovim charts as a visual reference; Volt provides bar and indexed dot graphs for the initial dashboard

### Custom Query Charts
- Let users turn a query result into a chart on the selected database's dashboard
- Offer Volt's bar and indexed dot graphs as the initial chart types
- Let users map query-result columns to labels and numeric values; convert those rows into Volt's graph data and scale values while preserving the original numbers in labels
- Preview the chart and save its query, database, chart type, and column mappings so it can be refreshed rather than saving only a snapshot
- Refresh user charts on demand; limit plotted rows and avoid automatically rerunning arbitrary or mutating SQL when the dashboard opens

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
- Explore dashboard data sources beyond databases after the local dashboard proves useful:
  - Datadog: investigate API-backed metrics/time-series charts and log queries
  - Confluent: investigate topic throughput, consumer lag, and available query APIs
  - Assess authentication, API limits, and which views fit Enhance before committing to either integration

## v2.0 (and future support)

### NoSQL Database Support
- Redis / **MongoDB**
  - JSON query input (e.g., `db.users.find({ age: { $gt: 25 } })`)
  - Pretty-printed JSON document output
  - Collection browser (not table-based)
  - Document viewer with syntax highlighting
  - Basic `find()` queries only
  - No aggregation pipelines initially
