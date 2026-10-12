// One stdin request and one connection; SQL is sent as one native Query message.
package main

import (
    "context"
    "encoding/hex"
    "encoding/json"
    "errors"
    "fmt"
    "io"
    "os"
    "strconv"
    "strings"
    "time"
    "unicode/utf8"

    "github.com/jackc/pgx/v5/pgconn"
    "github.com/jackc/pgx/v5/pgproto3"
)

type Connection struct {
    Server string `json:"server"`
    Port int `json:"port,omitempty"`
    Database string `json:"database"`
    User string `json:"user"`
    Password string `json:"password"`
    SSLMode string `json:"sslMode,omitempty"`
    TrustServerCertificate bool `json:"trustServerCertificate,omitempty"`
    ConnectTimeoutSeconds int `json:"connectTimeoutSeconds"`
}
type Request struct {
    Protocol int `json:"protocol"`
    DBType string `json:"dbType"`
    Query string `json:"query"`
    Connection Connection `json:"connection"`
    CommandTimeoutSeconds int `json:"commandTimeoutSeconds"`
}
type Column struct { Name string `json:"name"`; Type string `json:"type"`; Format int16 `json:"format"` }
type ResultSet struct { Columns []Column `json:"columns"`; Rows [][]*string `json:"rows"` }
type Diagnostic struct {
    Kind string `json:"kind,omitempty"`
    Message string `json:"message"`
    SQLState string `json:"sqlState,omitempty"`
    Number *int `json:"number"`
    Severity int `json:"severity"`
    State int `json:"state"`
    Line int `json:"line"`
}
type Response struct {
    Protocol int `json:"protocol"`
    OK bool `json:"ok"`
    ResultSets []ResultSet `json:"resultSets"`
    Messages []Diagnostic `json:"messages"`
    Errors []Diagnostic `json:"errors"`
    AffectedRows *int64 `json:"affectedRows"`
    DurationMs float64 `json:"durationMs"`
}
func response() Response { return Response{Protocol: 1, ResultSets: []ResultSet{}, Messages: []Diagnostic{}, Errors: []Diagnostic{}} }
func failure(kind, message string) Response { r := response(); r.Errors = append(r.Errors, Diagnostic{Kind: kind, Message: message}); return r }

func valid(r Request) bool {
    c := r.Connection
    if r.Protocol != 1 || r.DBType != "postgresql" || strings.TrimSpace(r.Query) == "" || strings.ContainsRune(r.Query, 0) ||
        strings.TrimSpace(c.Server) == "" || strings.TrimSpace(c.Database) == "" || strings.TrimSpace(c.User) == "" ||
        c.Port < 0 || c.Port > 65535 || c.ConnectTimeoutSeconds < 1 || c.ConnectTimeoutSeconds > 300 ||
        r.CommandTimeoutSeconds < 1 || r.CommandTimeoutSeconds > 86400 { return false }
    for _, value := range []string{c.Server, c.Database, c.User, c.Password} { if strings.ContainsRune(value, 0) { return false } }
    switch c.SSLMode { case "", "disable", "prefer", "require", "verify-ca", "verify-full": return !c.TrustServerCertificate; default: return false }
}

func config(c Connection) (*pgconn.Config, error) {
    quote := func(s string) string { return "'" + strings.ReplaceAll(strings.ReplaceAll(s, "\\", "\\\\"), "'", "\\'") + "'" }
    port := c.Port; if port == 0 { port = 5432 }
    mode := c.SSLMode; if mode == "" { mode = "prefer" }
    // Explicit empty file settings avoid silently borrowing another connection's credentials.
    settings := "host=" + quote(c.Server) + " port=" + strconv.Itoa(port) + " dbname=" + quote(c.Database) +
        " user=" + quote(c.User) + " password=" + quote(c.Password) + " sslmode=" + mode +
        " passfile='' sslcert='' sslkey='' sslrootcert='' connect_timeout=" + strconv.Itoa(c.ConnectTimeoutSeconds)
    cfg, err := pgconn.ParseConfig(settings)
    if err != nil { return nil, err }
    cfg.RuntimeParams = map[string]string{"client_encoding": "UTF8", "application_name": "enhance.nvim helper"}
    cfg.ValidateConnect, cfg.AfterConnect = nil, nil // Never issue a hidden query before user SQL.
    return cfg, nil
}

func execute(ctx context.Context, req Request) Response {
    r := response()
    timer := time.Now()
    err := query(ctx, req, &r)
    if err != nil && len(r.Errors) == 0 { r.Errors = append(r.Errors, Diagnostic{Kind: "transport_error", Message: "PostgreSQL helper connection or query failed."}) }
    r.OK = err == nil && len(r.Errors) == 0
    r.DurationMs = float64(time.Since(timer).Microseconds()) / 1000
    return r
}

func query(ctx context.Context, req Request, r *Response) error {
    cfg, err := config(req.Connection)
    if err != nil { return err }
    safe := func(s string) string { if req.Connection.Password != "" { return strings.ReplaceAll(s, req.Connection.Password, "[redacted]") }; return s }
    diagnostic := func(kind string, e *pgconn.PgError) Diagnostic {
        if !utf8.ValidString(e.Message) || !utf8.ValidString(e.Code) {
            return Diagnostic{Kind: "unsupported_encoding", Message: "A PostgreSQL diagnostic is not valid UTF-8."}
        }
        return Diagnostic{Kind: kind, Message: safe(e.Message), SQLState: e.Code}
    }
    cfg.OnNotice = func(_ *pgconn.PgConn, notice *pgconn.Notice) {
        // Legacy diagnostic fields remain integers, but PostgreSQL SQLSTATE stays text.
        d := diagnostic("", (*pgconn.PgError)(notice)); zero := 0; d.Number = &zero
        if d.Kind != "" { r.Errors = append(r.Errors, d) } else { r.Messages = append(r.Messages, d) }
    }
    connectCtx, cancel := context.WithTimeout(ctx, time.Duration(req.Connection.ConnectTimeoutSeconds)*time.Second)
    conn, err := pgconn.ConnectConfig(connectCtx, cfg)
    cancel()
    if err != nil { return err }
    defer func() { closeCtx, stop := context.WithTimeout(context.Background(), time.Second); defer stop(); conn.Close(closeCtx) }()
    commandCtx, stop := context.WithTimeout(ctx, time.Duration(req.CommandTimeoutSeconds)*time.Second)
    defer stop()
    // Use the driver's frontend directly so COPY cannot be silently consumed by Exec's result iterator.
    // ReceiveMessage still owns authentication-independent notices, error handling and read deadlines.
    conn.Frontend().SendQuery(&pgproto3.Query{String: req.Query})
    conn.Conn().SetWriteDeadline(time.Now().Add(time.Duration(req.CommandTimeoutSeconds)*time.Second))
    if err := conn.Frontend().Flush(); err != nil { return err }
    conn.Conn().SetWriteDeadline(time.Time{})
    var current *ResultSet
    unsupported := func(kind string) error {
        r.Errors = append(r.Errors, Diagnostic{Kind: kind, Message: "PostgreSQL helper cannot safely represent this result protocol or encoding."})
        return errors.New(kind)
    }
    for {
        msg, err := conn.ReceiveMessage(commandCtx)
        if err != nil {
            var pgErr *pgconn.PgError
            if errors.As(err, &pgErr) { r.Errors = append(r.Errors, diagnostic("sql_error", pgErr)) }
            return err
        }
        switch m := msg.(type) {
        case *pgproto3.RowDescription:
            if current != nil { return unsupported("invalid_result") }
            if conn.ParameterStatus("client_encoding") != "UTF8" { return unsupported("unsupported_encoding") }
            current = &ResultSet{Columns: []Column{}, Rows: [][]*string{}}
            for _, f := range m.Fields {
                if !utf8.Valid(f.Name) || (f.Format != 0 && f.Format != 1) { return unsupported("unsupported_encoding") }
                current.Columns = append(current.Columns, Column{string(f.Name), fmt.Sprintf("oid:%d", f.DataTypeOID), f.Format})
            }
        case *pgproto3.DataRow:
            if current == nil || len(m.Values) != len(current.Columns) { return unsupported("invalid_result") }
            row := make([]*string, len(m.Values))
            for i, value := range m.Values {
                if value == nil { continue }
                var text string
                if current.Columns[i].Format == 1 { text = "0x" + strings.ToUpper(hex.EncodeToString(value)) } else {
                    if conn.ParameterStatus("client_encoding") != "UTF8" || !utf8.Valid(value) { return unsupported("unsupported_encoding") }
                    text = string(value)
                }
                row[i] = &text
            }
            current.Rows = append(current.Rows, row)
        case *pgproto3.CommandComplete:
            if current != nil { r.ResultSets = append(r.ResultSets, *current); current = nil }
            tag := pgconn.NewCommandTag(string(m.CommandTag))
            if tag.Insert() || tag.Update() || tag.Delete() || strings.HasPrefix(tag.String(), "MERGE ") {
                if r.AffectedRows == nil { var zero int64; r.AffectedRows = &zero }
                *r.AffectedRows += tag.RowsAffected()
            }
        case *pgproto3.ErrorResponse:
            r.Errors = append(r.Errors, diagnostic("sql_error", pgconn.ErrorResponseToPgError(m)))
            current = nil // An interrupted result is not a completed result set.
        case *pgproto3.CopyInResponse, *pgproto3.CopyOutResponse, *pgproto3.CopyBothResponse:
            return unsupported("unsupported_copy")
        case *pgproto3.ReadyForQuery:
            if current != nil { return unsupported("invalid_result") }
            return nil
        case *pgproto3.ParameterStatus, *pgproto3.NoticeResponse, *pgproto3.NotificationResponse, *pgproto3.EmptyQueryResponse:
            // Handled by pgconn or valid responses without a tabular result.
        default:
            return unsupported("invalid_result")
        }
    }
}

func run(input io.Reader, output io.Writer, args []string) int {
    // This is a dedicated one-request child, not Neovim's process environment.
    for _, item := range os.Environ() { key, _, _ := strings.Cut(item, "="); if strings.HasPrefix(key, "PG") { os.Unsetenv(key) } }
    if len(args) == 1 && args[0] == "--version" { fmt.Fprintln(output, `{"protocol":1,"helperVersion":"1.1.1","dbType":"postgresql"}`); return 0 }
    r := failure("invalid_request", "Expected a valid protocol-1 PostgreSQL request on stdin.")
    data, err := io.ReadAll(io.LimitReader(input, 16*1024*1024+1))
    if len(args) == 0 && err == nil && len(data) <= 16*1024*1024 && utf8.Valid(data) {
        decoder := json.NewDecoder(strings.NewReader(string(data))); decoder.DisallowUnknownFields()
        var req Request
        if decoder.Decode(&req) == nil && valid(req) {
            var extra any
            if decoder.Decode(&extra) == io.EOF { r = execute(context.Background(), req) }
        }
    }
    if json.NewEncoder(output).Encode(r) != nil { return 1 }
    if r.OK { return 0 }; return 1
}
func main() { os.Exit(run(os.Stdin, os.Stdout, os.Args[1:])) }
