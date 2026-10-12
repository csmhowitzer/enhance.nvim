# Structured Helper Protocol

## Purpose
- Integration contract for driver-backed SQL Server/MySQL/PostgreSQL query execution. Both checked-in release pins remain unpublished; execution fails explicitly when a verified helper is unavailable.
- Implementations: `~/plugins/enhance.nvim/helper/` (.NET SqlClient/MySqlConnector) and `~/plugins/enhance.nvim/helper-postgres/` (Go pgconn/pgproto3). Protocol version: 1. Current source handshake: 1.1.1; the earlier local SQL Server-only binary reports 1.0.0.

## Process Boundary
- One process accepts one JSON request on stdin through EOF, then writes one JSON response to stdout. No query or credentials are accepted through process arguments or emitted as diagnostics.
- `--version` returns protocol/helperVersion without reading stdin or connecting. The PostgreSQL companion also reports dbType=postgresql.
- Success exits 0; errors exit 1. Stdout is always structured JSON; there is no raw-output fallback.
- Requests larger than 16,777,216 UTF-16 characters are rejected. UTF-8 is used for the process streams.

## Request

```json
{
  "protocol": 1,
  "query": "SELECT 'hello|world';",
  "connection": {
    "server": "example-server",
    "database": "example-database",
    "user": "example-reader",
    "password": "example-placeholder",
    "trustServerCertificate": false,
    "connectTimeoutSeconds": 15
  },
  "commandTimeoutSeconds": 30
}
```

- Required fields: protocol, query, connection, server, database. Unknown fields are rejected. Protocol must equal 1; query/server/database must not be blank.
- Omit user/password for integrated authentication; it depends on the host's authentication prerequisites. SQL authentication uses the supplied user and optional password. A password without a user is rejected.
- Connection timeout defaults to 15 seconds and permits 1–300. Command timeout defaults to 30 seconds and permits 1–86,400. Unlimited timeouts are not supported by this initial contract.
- TLS encryption is mandatory. Certificate validation is on unless trustServerCertificate is explicitly true. Connection strings are constructed through SqlConnectionStringBuilder, never concatenated from values.

### MySQL and PostgreSQL Requests
- Add dbType=mysql or dbType=postgresql. Omitted dbType remains SQL Server for protocol compatibility. Select the PostgreSQL executable separately; do not send its request to the main .NET helper.
- connection.port is a separate integer for these engines, unlike SQL Server's server,port address. connection.sslMode accepts disable/prefer/require/verify-ca/verify-full; prefer is the CLI-compatible default, not a certificate-validation guarantee. trustServerCertificate=true is rejected for these engines.
- PostgreSQL requires explicit user/username and rejects NUL in query text (the server wire Query string is NUL-terminated). It clears inherited PG settings inside its own child process and disables implicit pass/cert file settings; Neovim's environment is not mutated. Startup requests UTF8 without an extra SQL command.
- .NET input is bounded to 16 Mi UTF-16 characters; PostgreSQL input to 16 Mi UTF-8 bytes. Unknown JSON members and invalid versions/endpoints/timeouts fail closed.

### Engine-Specific Result Values
- MySQL DECIMAL uses GetMySqlDecimal, unsigned integers retain their full range, binary(16) is not guessed as a GUID, and tinyint(1) is not guessed as a boolean. MySqlDateTime values retain all components, including partial-zero dates and microseconds, using invariant formatting rather than its lossy ToString implementation.
- PostgreSQL reads native RowDescription/DataRow/CommandComplete messages through pgconn. Names and cells remain positional; empty sets retain headers before any row arrives. Text uses server representations (including numeric/array/custom values); binary cursor cells use 0x uppercase hex with native format codes retained as column_formats. Type identity is reported as oid:N, not a guessed display name or extra catalog query.
- PostgreSQL bytea in text mode retains the server's escaped representation; arbitrary binary-format cursor values retain exact bytes through hex. Non-UTF8 text/diagnostics or client_encoding changes that cannot be represented safely produce explicit errors, not replacement characters.
- SQLSTATE remains a separate sqlState string on native SQL errors. PostgreSQL affectedRows aggregates INSERT/UPDATE/DELETE/MERGE command tags only, including zero; returned SELECT/FETCH rows are counted separately. Notices/errors do not become cells.
- PostgreSQL COPY IN/OUT/BOTH responses fail explicitly as unsupported_copy. The helper never discards COPY output, waits indefinitely for stdin data, rewrites SQL to avoid COPY, or replays it.
- MySQL warning text is not fetched with an additional SHOW WARNINGS query; the helper does not claim full CLI warning-message parity. This does not affect positional returned cell fidelity.

## Response

```json
{
  "protocol": 1,
  "ok": true,
  "resultSets": [
    {
      "columns": [
        { "name": "message", "type": "nvarchar" },
        { "name": "empty", "type": "varchar" },
        { "name": "missing", "type": "varchar" }
      ],
      "rows": [["hello|world\nsecond line", "", null]]
    }
  ],
  "messages": [],
  "errors": [],
  "affectedRows": null,
  "durationMs": 1.5
}
```

- Column names/types and row values are positional arrays, preserving duplicate or unnamed columns. Empty result sets retain columns and an empty rows array.
- SQL NULL is JSON null; empty text is an empty JSON string. Text retains whitespace, pipes, CR/LF, tabs, NULs, backslashes, and Unicode without SQL CLI formatting or width limits.
- Non-null scalar values are invariant strings, avoiding JSON numeric precision loss. SQL decimals use SqlDecimal to handle 38-digit precision; timestamps use round-trip formatting; binary values are uppercase hexadecimal prefixed with `0x`; booleans are `true`/`false` strings.
- Unsupported values produce an unsupported_value error rather than guessed text. XML values use the driver's SQL XML representation.
- Messages contain message, number, severity, state, and line. Errors contain kind, message, and optional number/severity/state/line. Error kinds include invalid_request, sql_error, cancelled, unsupported_value, and internal_error.
- Driver messages/errors redact the configured password. Invalid input and unexpected exceptions return generic errors without echoing input, stack traces, SQL, or connection strings. Database-provided messages may still contain application data and should not be logged indiscriminately.
- affectedRows is the driver's aggregate RecordsAffected when available; null means unavailable. It is not a per-statement attribution. durationMs measures driver execution including connection establishment.
- A sql_error response can retain fully captured earlier result sets; `ok: false` must not be treated as a successful query merely because rows are present.

## Lua Adapter Boundary
- `require('enhance.db.sqlserver_helper')` exposes two internal, pure functions. Neither starts a process, resolves/downloads a helper, nor calls the legacy text parser.
- `encode_request(connection, query, opts)` returns a JSON stdin body or nil plus a generic validation error. SQL is copied unchanged; credentials are fields in stdin, never argv. Server/host and user/username aliases are supported, with the primary field taking precedence.
- A separate numeric port is appended as `server,port`. A server already containing a comma or named-instance separator plus a separate port is rejected rather than guessed. Omit the separate port to use a complete endpoint string unchanged.
- Certificate validation defaults on; only an explicit boolean `trust_server_certificate = true` opts out. Optional `connect_timeout_seconds` and `command_timeout_seconds` use the protocol's bounds/defaults. The legacy CLI's implicit certificate-trust default is not copied.
- `decode_response(stdout, exit_code)` validates complete JSON and exit status before returning normalized data. Exit 0 must agree with ok=true and no errors; exit 1 must agree with ok=false and at least one error. Other statuses, invalid shapes/types/row widths, unsupported versions, and trailing output return nil plus a generic protocol error without echoing stdout.
- A valid response returns `ok`, `parsed_result`, `messages`, `errors`, `affected_rows`, and `duration_ms`. A structured SQL error remains a response with ok=false, possibly retaining earlier complete result sets; callers must check ok before treating data as successful.
- `parsed_result` uses positional headers, column_types, rows, and metadata. Multiple sets use multiple_results/result_sets; empty sets retain metadata. Header names are not normalized or used as object keys. Cells remain strings or `vim.NIL`, including trailing NULLs.
- `affected_rows` retains JSON null as `vim.NIL` and stays at envelope level; it is not assigned to any result set's row_count. Messages/errors remain structured, not interleaved with table cells.
- Result consumers accept explicit NULLs: formatting uses the configured NULL marker, preserves empty text, and retains raw values for copying/popups. Structured row maps carry explicit_nulls so literal NULL text is not styled or sampled as a database NULL. JSON detection skips actual NULLs but treats structured empty/literal-NULL strings as values. Legacy CLI NULL-marker behavior is retained separately for other paths; CLI text cannot establish exact NULL identity.

## Asynchronous Process Runner
- `require('enhance.helper_runner').new()` creates one request owner. `runner:run(connection, query, callback, opts)` validates/encodes the request, resolves only a verified cached helper, and launches it directly with `vim.system`. It never installs/downloads a helper or waits synchronously for SQL execution. Cache checksum lookup itself remains synchronous.
- The executable is the only argv entry. The request is a string stdin body, which Neovim writes and closes through EOF. Output is captured without text-mode CR/LF normalization; stderr is discarded, never shown as a fallback or appended to errors.
- Every completion callback is scheduled with `(response, error)`. Valid SQL error envelopes are responses with ok=false; startup/protocol/process failures instead return nil and a generic error. A timeout reports a transport error, not a successful partial result.
- A process deadline defaults to connect timeout + command timeout + five seconds. `process_timeout_ms` optionally overrides it with an integer from 1 to 90,000,000 milliseconds; the deadline can expire during connection, query execution, or serialization/output.
- A new request supersedes the owner's previous request, attempts to terminate any still-running process, and suppresses all predecessor callbacks, including already scheduled results. The executor owns one runner per query buffer (one shared anonymous owner when no buffer is supplied), with an additional generation guard. BufWipeout and VimLeavePre cancel and detach owners; callbacks from deleted buffers are not rendered. `require('enhance.executor').cancel_sqlserver(query_bufnr)` cancels/detaches a specific owner, or the anonymous owner if omitted.
- `runner:cancel()` returns true when it first cancels an owned request, false when idle or already cancelled. It replaces undelivered results with one scheduled cancellation and ignores subsequent exits. Running processes are sent SIGKILL; termination exceptions are caught without echoing diagnostics. There is no SQL retry or inferred rollback; cancellation/timeout does not prove whether preceding writes committed.
- Mocked lifecycle regressions cover startup, exit/protocol errors, cancellation, timeouts, supersession, isolation, and callback reentrancy. Real subprocess fixture tests verify stdin/EOF, exact text and NULLs, actual cancellation exit, and process deadlines without connecting to a database. Python 3 is a test-fixture dependency, not an end-user dependency.
- Response capture is buffered; bounded execution time does not bound result memory. Streaming/size policy and actual SQL Server cancellation outcomes remain validation considerations. Workspace cleanup must wipe/cancel its query buffers; the separate workspace lifecycle review remains pending.

## Query Execution and Rendering
- SQL Server/MySQL/PostgreSQL execution uses one unchanged query per command/connection and structured rendering, even with format_results=false. CLI query collectors and their ambiguous framing are removed. Explorer/catalog/probe paths remain separate CLI operations. Explicit synchronous MySQL/PostgreSQL adapter calls also use verified helpers with bounded waits, not CLI parsing.
- Structured result sets render with native positional column types, exact original cell values, and NULL-aware row maps. Empty and multiple result sets are retained; display truncation does not truncate copied values. SQL Server results always use this rendering even when the legacy format_results option is false.
- Database messages and errors are appended after the formatted tables and also retained as separate structured metadata. No ordering between messages and result sets is inferred from this protocol. A failed query can retain earlier fully captured result sets and is still marked as an error.
- Returned table-row counts are summed independently of the aggregate affected_rows count, which is shown separately when supplied by the driver. No per-statement timing, affected-row attribution, implicit transaction, or forced stop-on-error policy is invented.
- Missing/corrupt/unpublished helpers, process failures, and invalid responses produce explicit errors with empty parsed/row metadata rather than a raw text fallback. Queries do not download or build an executable.

## Execution Semantics and Remaining Gates
- The query is assigned unchanged to one SqlCommand on one connection. No JSON clause, implicit transaction, keyword-based splitting, or SQL replay is added. Connections do not persist between helper invocations.
- SqlCommand accepts server SQL, not SQLCMD scripting. GO, SQLCMD variables/directives, and includes are unsupported; no scripting preprocessor or text fallback is used. Queries are sent unchanged, so SQL Server reports unsupported syntax as an error. This limitation must be visible in public documentation rather than advertised as compatible script execution.
- SQL authentication and integrated authentication construction are tested without connecting. Live authentication, batch/transaction behavior, row counts, PRINT/error ordering, and actual SqlDataReader metadata require live database verification.
- Ctrl-C cancellation is passed through to the driver by the helper. The Lua runner uses process termination instead; live server cancellation outcomes remain pending. No cancellation keymap is added by this integration.
- Lua decoding, NULL-aware consumers, lifecycle, and the public executor-to-subprocess-to-decoder-to-formatter path are tested with a database-free fixture. A self-contained helper invalid-request envelope is also tested without connecting to SQL Server. These are not a substitute for successful live SQL Server authentication/query validation or public-release installation verification.
- Move to a supported LTS .NET target before public release; current local verification used net8.0/runtime 8.0.31, which reaches end of support on 2026-11-10.
- PostgreSQL sends one native simple Query message unchanged, preserving the server's implicit-transaction/stop-on-error behavior. It uses pgconn's frontend/ReceiveMessage directly so COPY responses can be rejected rather than swallowed by the driver's generic result iterator. MySQL uses one unprepared text command, no parameters/debatching/probes; MySqlConnector still applies its own ordinary parameter lexer and can append a newline to terminate a trailing comment. Do not claim byte-for-byte MySQL wire identity from CommandText assignment alone.
- Live edge-case scripts: `~/plugins/enhance.nvim/tests/fixtures/c03-sqlserver.sql`, `~/plugins/enhance.nvim/tests/fixtures/c03-mysql.sql`, `~/plugins/enhance.nvim/tests/fixtures/c03-postgres.sql`. User-authorized ML Docker checks passed on 2026-10-09 through the real executor/runner/decoder/formatter, including exact clipboard/popup values and retained earlier results on later errors. C03 is closed. Opt-in regression: `~/plugins/enhance.nvim/tests/c03_live_spec.lua` (ENHANCE_C03_LIVE=1 under nvt); ordinary tests never load personal credentials or contact databases. Additional TLS/authentication modes, live cancellation/rollback, and other platforms are not covered by those read-only checks.
