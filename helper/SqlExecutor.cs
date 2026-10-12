using System.Diagnostics;
using Microsoft.Data.SqlClient;

namespace Enhance.Helper;

public sealed class SqlExecutor : IQueryExecutor
{
    public static SqlConnectionStringBuilder BuildConnection(ConnectionOptions options)
    {
        var builder = new SqlConnectionStringBuilder {
            DataSource = options.Server, InitialCatalog = options.Database,
            ConnectTimeout = options.ConnectTimeoutSeconds,
            Encrypt = SqlConnectionEncryptOption.Mandatory,
            TrustServerCertificate = options.TrustServerCertificate,
            PersistSecurityInfo = false, ApplicationName = "enhance.nvim helper",
            // A helper owns one connection for one request, not a persistent session.
            Pooling = false
        };
        if (options.User is not null) {
            builder.UserID = options.User;
            builder.Password = options.Password ?? "";
        } else {
            builder.IntegratedSecurity = true;
        }
        return builder;
    }

    public async Task<HelperResponse> ExecuteAsync(HelperRequest request, CancellationToken cancellationToken)
    {
        var response = new HelperResponse();
        var timer = Stopwatch.StartNew();
        string Safe(string message) => string.IsNullOrEmpty(request.Connection.Password)
            ? message : message.Replace(request.Connection.Password, "[redacted]", StringComparison.Ordinal);
        try {
            await using var connection = new SqlConnection(BuildConnection(request.Connection).ConnectionString);
            connection.InfoMessage += (_, args) => {
                foreach (SqlError message in args.Errors)
                    response.Messages.Add(new(Safe(message.Message), message.Number, message.Class, message.State, message.LineNumber));
            };
            await connection.OpenAsync(cancellationToken);
            await using var command = connection.CreateCommand();
            command.CommandText = request.Query;
            command.CommandTimeout = request.CommandTimeoutSeconds;
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            await ReaderMapper.ReadAsync(reader, cancellationToken, response.ResultSets);
            var affected = reader.RecordsAffected;
            response.AffectedRows = affected >= 0 ? affected : null;
            response.Ok = true;
        }
        catch (SqlException error) {
            foreach (SqlError detail in error.Errors)
                response.Errors.Add(new("sql_error", Safe(detail.Message), detail.Number, detail.Class, detail.State, detail.LineNumber));
        }
        finally { response.DurationMs = timer.Elapsed.TotalMilliseconds; }
        return response;
    }
}
