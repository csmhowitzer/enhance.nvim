using System.Diagnostics;
using MySqlConnector;

namespace Enhance.Helper;

public sealed class MySqlExecutor : IQueryExecutor
{
    public static MySqlConnectionStringBuilder BuildConnection(ConnectionOptions options) => new() {
        Server = options.Server, Port = (uint)(options.Port ?? 3306), Database = options.Database,
        UserID = options.User ?? "", Password = options.Password ?? "",
        ConnectionTimeout = (uint)options.ConnectTimeoutSeconds, Pooling = false,
        AllowUserVariables = true, AllowZeroDateTime = true, GuidFormat = MySqlGuidFormat.None,
        TreatTinyAsBoolean = false, UseAffectedRows = true,
        // Preserve binary(16) bytes instead of converting them into guessed GUID values.
        SslMode = (options.SslMode ?? "prefer") switch {
            "disable" => MySqlSslMode.Disabled, "prefer" => MySqlSslMode.Preferred,
            "require" => MySqlSslMode.Required, "verify-ca" => MySqlSslMode.VerifyCA,
            "verify-full" => MySqlSslMode.VerifyFull, _ => throw new ArgumentException()
        }
    };

    public async Task<HelperResponse> ExecuteAsync(HelperRequest request, CancellationToken cancellationToken)
    {
        var response = new HelperResponse();
        var timer = Stopwatch.StartNew();
        string Safe(string text) => string.IsNullOrEmpty(request.Connection.Password) ? text
            : text.Replace(request.Connection.Password, "[redacted]", StringComparison.Ordinal);
        try {
            await using var connection = new MySqlConnection(BuildConnection(request.Connection).ConnectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = connection.CreateCommand();
            command.CommandText = request.Query;
            command.CommandTimeout = request.CommandTimeoutSeconds;
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            await ReaderMapper.ReadAsync(reader, cancellationToken, response.ResultSets);
            response.AffectedRows = reader.RecordsAffected >= 0 ? reader.RecordsAffected : null;
            response.Ok = true;
        }
        catch (MySqlException error) {
            response.Errors.Add(new("sql_error", Safe(error.Message), error.Number, SqlState: error.SqlState));
        }
        finally { response.DurationMs = timer.Elapsed.TotalMilliseconds; }
        return response;
    }
}

public sealed class DriverExecutor : IQueryExecutor
{
    public Task<HelperResponse> ExecuteAsync(HelperRequest request, CancellationToken cancellationToken) =>
        (request.DbType == "mysql" ? (IQueryExecutor)new MySqlExecutor() : new SqlExecutor()).ExecuteAsync(request, cancellationToken);
}
