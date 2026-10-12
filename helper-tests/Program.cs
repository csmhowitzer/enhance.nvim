using System.Data;
using System.Data.SqlTypes;
using System.Globalization;
using System.Text.Json;
using Enhance.Helper;

var results = new List<object>();
async Task Test(string name, Func<Task> action)
{
    try { await action(); results.Add(new { name, ok = true, error = "" }); }
    catch (Exception error) { results.Add(new { name, ok = false, error = error.ToString() }); }
}
void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}
var request = new HelperRequest {
    Protocol = 1, Query = "  SELECT 'a|b', 'a--b';\n-- keep this comment\n",
    Connection = new ConnectionOptions { Server = "unused", Database = "unused" }
};
string Json(object value) => JsonSerializer.Serialize(value, HelperProtocol.JsonOptions);

await Test("preserves text, null positions, and empty result metadata", async () => {
    var table = new DataTable();
    table.Columns.Add("text", typeof(string));
    table.Columns.Add("blank", typeof(string));
    table.Columns.Add("null", typeof(string));
    var text = "  a|b\r\nc\t\\\0雪  " + new string('x', 10000);
    table.Rows.Add(text, "", DBNull.Value);
    var empty = table.Clone();
    using var reader = new DataTableReader(new[] { table, empty });
    var sets = await ReaderMapper.ReadAsync(reader, CancellationToken.None);
    Check(sets.Count == 2 && sets[1].Columns.Count == 3 && sets[1].Rows.Count == 0, "Empty set metadata lost");
    var row = sets[0].Rows[0];
    Check(row.Length == 3 && row[0] == text && row[1] == "" && row[2] is null, "Cell contents changed");
    var roundtrip = JsonSerializer.Deserialize<List<ResultSet>>(Json(sets), HelperProtocol.JsonOptions)!;
    Check(roundtrip[0].Rows[0][0] == text, "JSON did not roundtrip exact text");
});

await Test("keeps positional duplicate and unnamed column metadata", () => {
    var set = new ResultSet { Columns = new() { new("", "nvarchar"), new("same", "int"), new("same", "int") },
        Rows = new() { new string?[] { "", "1", "2" } } };
    var copy = JsonSerializer.Deserialize<ResultSet>(Json(set), HelperProtocol.JsonOptions)!;
    Check(copy.Columns.Count == 3 && copy.Columns[0].Name == "" && copy.Rows[0][2] == "2", "Columns collapsed");
    return Task.CompletedTask;
});

await Test("preserves precision, binary bytes, and invariant scalar values", () => {
    var previous = CultureInfo.CurrentCulture;
    try {
        CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("fr-FR");
        Check(ValueEncoder.Encode(123.45m) == "123.45", "Decimal locale changed");
        var large = "12345678901234567890123456789012345678";
        Check(ValueEncoder.Encode(SqlDecimal.Parse(large)) == large, "SQL decimal precision lost");
        Check(ValueEncoder.Encode(new SqlDecimal(123.45m)) == "123.45", "SQL decimal locale changed");
        Check(ValueEncoder.Encode(new byte[] { 0, 10, 255 }) == "0x000AFF", "Binary bytes lost");
        Check(ValueEncoder.Encode(SqlString.Null) is null, "Sql NULL lost");
        Check(ValueEncoder.Encode("NULL") == "NULL", "Literal NULL changed");
        Check(ValueEncoder.Encode(true) == "true", "Boolean changed");
    } finally { CultureInfo.CurrentCulture = previous; }
    return Task.CompletedTask;
});

await Test("submits unchanged SQL without putting input on stdout", async () => {
    HelperRequest? received = null;
    var runner = new FakeExecutor((value, _) => {
        received = value;
        return Task.FromResult(new HelperResponse { Ok = true });
    });
    var output = new StringWriter();
    var code = await HelperHost.RunAsync(new StringReader(Json(request)), output, Array.Empty<string>(), runner);
    Check(code == 0 && received!.Query == request.Query, "SQL changed");
    Check(!output.ToString().Contains(request.Query), "SQL echoed to stdout");
    Check(JsonDocument.Parse(output.ToString()).RootElement.GetProperty("protocol").GetInt32() == 1, "Protocol missing");
});

await Test("rejects invalid input without exposing secrets or executing", async () => {
    var runner = new FakeExecutor((_, _) => throw new Exception("must not execute"));
    foreach (var input in new[] { "{secret-password", Json(request with { Protocol = 2 }),
        Json(request with { Query = " " }), "null", "{}" }) {
        var output = new StringWriter();
        var code = await HelperHost.RunAsync(new StringReader(input), output, Array.Empty<string>(), runner);
        Check(code != 0 && !output.ToString().Contains("secret-password"), "Unsafe invalid request response");
        Check(JsonDocument.Parse(output.ToString()).RootElement.GetProperty("errors")[0].GetProperty("kind").GetString() == "invalid_request", "Wrong error kind");
    }
});

await Test("rejects command-line credentials without echoing them", async () => {
    var output = new StringWriter();
    var code = await HelperHost.RunAsync(new StringReader(""), output, new[] { "secret-password" },
        new FakeExecutor((_, _) => throw new Exception("must not execute")));
    Check(code != 0 && !output.ToString().Contains("secret-password"), "Arguments leaked");
});

await Test("exposes a structured version handshake without a connection", async () => {
    var output = new StringWriter();
    var code = await HelperHost.RunAsync(new StringReader(""), output, new[] { "--version" },
        new FakeExecutor((_, _) => throw new Exception("must not execute")));
    Check(code == 0 && JsonDocument.Parse(output.ToString()).RootElement.GetProperty("protocol").GetInt32() == 1, "Handshake failed");
});

await Test("handles cancellation and unexpected errors without diagnostics leakage", async () => {
    foreach (var error in new Exception[] { new OperationCanceledException(), new Exception("secret-password") }) {
        var output = new StringWriter();
        var code = await HelperHost.RunAsync(new StringReader(Json(request)), output, Array.Empty<string>(),
            new FakeExecutor((_, _) => throw error));
        Check(code != 0 && !output.ToString().Contains("secret-password"), "Error details leaked");
        var kind = JsonDocument.Parse(output.ToString()).RootElement.GetProperty("errors")[0].GetProperty("kind").GetString();
        Check(kind == (error is OperationCanceledException ? "cancelled" : "internal_error"), "Wrong error kind");
    }
});

await Test("builds authentication and TLS options without connection string injection", () => {
    var connection = new ConnectionOptions { Server = "example", Database = "db;Password=injected", User = "reader", Password = "p;word" };
    var builder = SqlExecutor.BuildConnection(connection);
    Check(builder.InitialCatalog == connection.Database && builder.Password == "p;word", "Connection string injection");
    Check(!builder.IntegratedSecurity && !builder.TrustServerCertificate
        && builder.Encrypt.Equals(Microsoft.Data.SqlClient.SqlConnectionEncryptOption.Mandatory), "Unsafe connection defaults");
    Check(SqlExecutor.BuildConnection(new ConnectionOptions { Server = "example", Database = "db" }).IntegratedSecurity, "Integrated authentication lost");
    return Task.CompletedTask;
});

await Test("preserves messages, errors, counts, and timestamps in the protocol", () => {
    var response = new HelperResponse {
        Ok = false, AffectedRows = 3, DurationMs = 1.5,
        Messages = new() { new("hello|world\nsecond line", 0, 0, 1, 2) },
        Errors = new() { new("sql_error", "constraint violation", 2627, 14, 1, 3) }
    };
    var copy = JsonSerializer.Deserialize<HelperResponse>(Json(response), HelperProtocol.JsonOptions)!;
    Check(copy.AffectedRows == 3 && copy.Messages[0].Message == response.Messages[0].Message
        && copy.Errors[0].Number == 2627 && !copy.Ok, "Response metadata lost");
    var date = new DateTimeOffset(2026, 10, 9, 12, 34, 56, TimeSpan.FromHours(2)).AddTicks(1234567);
    Check(ValueEncoder.Encode(date) == "2026-10-09T12:34:56.1234567+02:00", "Timestamp precision or offset lost");
    return Task.CompletedTask;
});

await Test("rejects unencodable values rather than inventing raw fallback cells", () => {
    try { ValueEncoder.Encode(new object()); throw new Exception("Unsupported value accepted"); }
    catch (UnsupportedValueException) { }
    return Task.CompletedTask;
});

await Test("honors reader cancellation", async () => {
    var table = new DataTable();
    table.Columns.Add("text", typeof(string));
    table.Rows.Add("value");
    using var reader = table.CreateDataReader();
    try {
        await ReaderMapper.ReadAsync(reader, new CancellationToken(true));
        throw new Exception("Cancelled reader accepted");
    } catch (OperationCanceledException) { }
});

await Test("builds MySQL endpoint, TLS and literal credentials without SQL rewriting", () => {
    var options = new ConnectionOptions { Server = "localhost", Port = 3307, Database = "db;Password=injected", User = "reader", Password = "p;word", SslMode = "disable" };
    var builder = MySqlExecutor.BuildConnection(options);
    Check(builder.Server == "localhost" && builder.Port == 3307 && builder.Database == options.Database && builder.Password == "p;word", "MySQL connection injection");
    Check(!builder.Pooling && builder.AllowUserVariables && builder.AllowZeroDateTime, "MySQL SQL/value compatibility lost");
    Check(ValueEncoder.Encode(ulong.MaxValue) == "18446744073709551615", "unsigned integer precision lost");
    Check(new HelperRequest { Protocol = 1, DbType = "mysql", Query = "SELECT 1; SELECT 2", Connection = options }.IsValid(), "MySQL request rejected");
    Check(!new HelperRequest { Protocol = 1, DbType = "other", Query = "SELECT 1", Connection = options }.IsValid(), "unknown driver accepted");
    return Task.CompletedTask;
});

await Test("preserves MySQL partial-zero dates, microseconds and integer identity", () => {
    var date = new MySqlConnector.MySqlDateTime(0, 12, 31, 12, 34, 56, 123456);
    Check(ValueEncoder.Encode(date) == "0000-12-31 12:34:56.123456", "Partial-zero date components lost");
    var builder = MySqlExecutor.BuildConnection(new ConnectionOptions { Server = "localhost", Database = "db" });
    Check(!builder.TreatTinyAsBoolean && builder.UseAffectedRows, "Integer or affected-count semantics changed");
    return Task.CompletedTask;
});

Console.WriteLine(JsonSerializer.Serialize(results));
return results.Any(value => JsonSerializer.Serialize(value).Contains("\"ok\":false")) ? 1 : 0;

sealed class FakeExecutor(Func<HelperRequest, CancellationToken, Task<HelperResponse>> run) : IQueryExecutor
{
    public Task<HelperResponse> ExecuteAsync(HelperRequest request, CancellationToken cancellationToken) => run(request, cancellationToken);
}
