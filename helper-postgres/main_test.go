package main

import (
    "context"
    "encoding/json"
    "net"
    "strings"
    "testing"
    "time"

    "github.com/jackc/pgx/v5/pgproto3"
)

// A real TCP protocol peer proves what the driver sends, not just a mock CommandText.
func peer(t *testing.T, messages []pgproto3.BackendMessage) (int, <-chan string) {
    t.Helper()
    listener, err := net.Listen("tcp", "127.0.0.1:0")
    if err != nil { t.Fatal(err) }
    t.Cleanup(func() { listener.Close() })
    received := make(chan string, 1)
    go func() {
        conn, err := listener.Accept()
        if err != nil { return }
        defer conn.Close()
        conn.SetDeadline(time.Now().Add(5*time.Second))
        backend := pgproto3.NewBackend(conn, conn)
        if _, err := backend.ReceiveStartupMessage(); err != nil { return }
        backend.Send(&pgproto3.AuthenticationOk{})
        backend.Send(&pgproto3.ParameterStatus{Name: "client_encoding", Value: "UTF8"})
        backend.Send(&pgproto3.ReadyForQuery{TxStatus: 'I'})
        if backend.Flush() != nil { return }
        msg, err := backend.Receive()
        if err != nil { return }
        if query, ok := msg.(*pgproto3.Query); ok { received <- query.String } else { received <- "not a simple Query" }
        if messages == nil { backend.Receive(); return } // Wait for the client deadline/close.
        for _, message := range messages { backend.Send(message) }
        backend.Send(&pgproto3.ReadyForQuery{TxStatus: 'I'})
        backend.Flush()
        backend.Receive()
    }()
    return listener.Addr().(*net.TCPAddr).Port, received
}

func request(port int) Request {
    return Request{Protocol: 1, DBType: "postgresql", Query: "  SELECT 'a;b--c';\nSELECT 2; ",
        Connection: Connection{Server: "127.0.0.1", Port: port, Database: "unused", User: "reader", SSLMode: "disable", ConnectTimeoutSeconds: 2},
        CommandTimeoutSeconds: 2}
}

func TestUnchangedSQLAndPositionalResults(t *testing.T) {
    text := "  a|b\r\n\t\\雪  " + strings.Repeat("x", 10000)
    columns := &pgproto3.RowDescription{Fields: []pgproto3.FieldDescription{
        {Name: []byte("same"), DataTypeOID: 25}, {Name: []byte("same"), DataTypeOID: 25}, {Name: []byte(""), DataTypeOID: 25}}}
    port, received := peer(t, []pgproto3.BackendMessage{columns,
        &pgproto3.DataRow{Values: [][]byte{[]byte(text), nil, {}}},
        &pgproto3.CommandComplete{CommandTag: []byte("SELECT 1")}, columns,
        &pgproto3.CommandComplete{CommandTag: []byte("SELECT 0")},
        &pgproto3.CommandComplete{CommandTag: []byte("UPDATE 0")}})
    req := request(port)
    response := execute(context.Background(), req)
    if !response.OK { t.Fatalf("%+v", response.Errors) }
    if got := <-received; got != req.Query { t.Fatalf("SQL changed: %q", got) }
    if len(response.ResultSets) != 2 || len(response.ResultSets[1].Columns) != 3 || len(response.ResultSets[1].Rows) != 0 { t.Fatal("empty set metadata lost") }
    row := response.ResultSets[0].Rows[0]
    if len(row) != 3 || row[0] == nil || *row[0] != text || row[1] != nil || row[2] == nil || *row[2] != "" { t.Fatal("cell fidelity lost") }
    if response.AffectedRows == nil || *response.AffectedRows != 0 { t.Fatal("zero DML count lost or SELECT rows counted") }
    data, err := json.Marshal(response)
    if err != nil || !json.Valid(data) { t.Fatal("invalid envelope") }
}

func TestEarlierResultsAndSQLState(t *testing.T) {
    port, _ := peer(t, []pgproto3.BackendMessage{
        &pgproto3.RowDescription{Fields: []pgproto3.FieldDescription{{Name: []byte("value"), DataTypeOID: 1700}}},
        &pgproto3.DataRow{Values: [][]byte{[]byte("123456789012345678901234567890.123456789")}},
        &pgproto3.CommandComplete{CommandTag: []byte("SELECT 1")},
        &pgproto3.NoticeResponse{Severity: "NOTICE", Code: "00000", Message: "hello|world"},
        &pgproto3.ErrorResponse{Severity: "ERROR", Code: "42P01", Message: "missing relation"}})
    response := execute(context.Background(), request(port))
    if response.OK || len(response.ResultSets) != 1 || len(response.Messages) != 1 || len(response.Errors) != 1 || response.Errors[0].SQLState != "42P01" { t.Fatalf("diagnostics/partial results lost: %+v", response) }
}

func TestBinaryCursorAndCopyRejection(t *testing.T) {
    port, _ := peer(t, []pgproto3.BackendMessage{
        &pgproto3.RowDescription{Fields: []pgproto3.FieldDescription{{Name: []byte("binary"), DataTypeOID: 17, Format: 1}}},
        &pgproto3.DataRow{Values: [][]byte{{0, 255, 10}}}, &pgproto3.CommandComplete{CommandTag: []byte("FETCH 1")}})
    response := execute(context.Background(), request(port))
    if !response.OK || *response.ResultSets[0].Rows[0][0] != "0x00FF0A" { t.Fatal("binary bytes lost") }
    for _, msg := range []pgproto3.BackendMessage{&pgproto3.CopyOutResponse{}, &pgproto3.CopyInResponse{}, &pgproto3.CopyBothResponse{}} {
        port, _ := peer(t, []pgproto3.BackendMessage{msg})
        response := execute(context.Background(), request(port))
        if response.OK || len(response.Errors) != 1 || response.Errors[0].Kind != "unsupported_copy" { t.Fatal("COPY silently accepted") }
    }
}

func TestInvalidTextIsNotReplaced(t *testing.T) {
    port, _ := peer(t, []pgproto3.BackendMessage{
        &pgproto3.RowDescription{Fields: []pgproto3.FieldDescription{{Name: []byte("value"), DataTypeOID: 25}}},
        &pgproto3.DataRow{Values: [][]byte{{255}}}, &pgproto3.CommandComplete{CommandTag: []byte("SELECT 1")}})
    response := execute(context.Background(), request(port))
    if response.OK || response.Errors[0].Kind != "unsupported_encoding" { t.Fatal("invalid UTF-8 silently replaced") }
}

func TestStrictInputAndNoSecretEcho(t *testing.T) {
    for _, input := range []string{"{secret-password", "null", "{}", `{"protocol":1,"unknown":true}`} {
        var output strings.Builder
        if run(strings.NewReader(input), &output, nil) != 1 || strings.Contains(output.String(), "secret-password") || !strings.Contains(output.String(), "invalid_request") { t.Fatal("invalid input accepted/leaked") }
    }
    var output strings.Builder
    if run(strings.NewReader(""), &output, []string{"--version"}) != 0 || !strings.Contains(output.String(), `"protocol":1`) { t.Fatal("handshake failed") }
}

func TestChildIgnoresInheritedEndpointCredentialsAndService(t *testing.T) {
    t.Setenv("PGSERVICE", "nonexistent-service")
    t.Setenv("PGHOST", "wrong-host")
    t.Setenv("PGPASSWORD", "other-password")
    port, received := peer(t, []pgproto3.BackendMessage{&pgproto3.CommandComplete{CommandTag: []byte("UPDATE 0")}})
    req := request(port)
    input, _ := json.Marshal(req)
    var output strings.Builder
    if run(strings.NewReader(string(input)), &output, nil) != 0 { t.Fatal(output.String()) }
    if got := <-received; got != req.Query { t.Fatal("inherited config changed execution") }
}

func TestQueryDeadlineAndNoReplay(t *testing.T) {
    port, received := peer(t, nil)
    req := request(port)
    req.CommandTimeoutSeconds = 1
    started := time.Now()
    response := execute(context.Background(), req)
    if response.OK || len(response.Errors) != 1 || time.Since(started) > 3*time.Second { t.Fatal("query deadline failed") }
    if sql := <-received; sql != req.Query { t.Fatal("SQL changed") }
    select { case <-received: t.Fatal("query replayed"); default: }
}

func TestCancellation(t *testing.T) {
    port, received := peer(t, nil)
    ctx, cancel := context.WithCancel(context.Background())
    done := make(chan Response, 1)
    go func() { done <- execute(ctx, request(port)) }()
    select { case <-received: case <-time.After(3*time.Second): t.Fatal("no query received") }
    cancel()
    select {
    case result := <-done: if result.OK { t.Fatal("cancelled query succeeded") }
    case <-time.After(3*time.Second): t.Fatal("cancellation did not return")
    }
}
