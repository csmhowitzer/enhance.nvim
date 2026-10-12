using System.Data.Common;
using System.Data.SqlTypes;
using System.Globalization;
using Microsoft.Data.SqlClient;
using MySqlConnector;

namespace Enhance.Helper;

public sealed class UnsupportedValueException : Exception;

public static class ValueEncoder
{
    /// <summary>Text values are untouched; scalars are invariant strings, not lossy JSON numbers.</summary>
    public static string? Encode(object? value)
    {
        if (value is null or DBNull || value is INullable { IsNull: true }) return null;
        return value switch {
            string text => text,
            char character => character.ToString(),
            bool boolean => boolean ? "true" : "false",
            byte[] bytes => "0x" + Convert.ToHexString(bytes),
            DateTime date => date.ToString("O", CultureInfo.InvariantCulture),
            DateTimeOffset date => date.ToString("O", CultureInfo.InvariantCulture),
            TimeSpan time => time.ToString("c", CultureInfo.InvariantCulture),
            Guid guid => guid.ToString("D"),
            byte or sbyte or short or ushort or int or uint or long or ulong or decimal => ((IFormattable)value).ToString(null, CultureInfo.InvariantCulture),
            MySqlDecimal number => number.ToString(),
            // ToString() is locale-sensitive and collapses partial-zero dates to 0000-00-00.
            MySqlDateTime date => FormattableString.Invariant($"{date.Year:D4}-{date.Month:D2}-{date.Day:D2} {date.Hour:D2}:{date.Minute:D2}:{date.Second:D2}.{date.Microsecond:D6}"),
            float number => number.ToString("R", CultureInfo.InvariantCulture),
            double number => number.ToString("R", CultureInfo.InvariantCulture),
            SqlDecimal number => number.ToString().Replace(CultureInfo.CurrentCulture.NumberFormat.NumberDecimalSeparator, "."),
            SqlString text => text.Value,
            SqlChars text => new string(text.Value),
            SqlXml xml => xml.Value,
            SqlBinary bytes => Encode(bytes.Value),
            SqlBytes bytes => Encode(bytes.Value),
            SqlBoolean boolean => Encode(boolean.Value),
            SqlByte number => Encode(number.Value),
            SqlInt16 number => Encode(number.Value),
            SqlInt32 number => Encode(number.Value),
            SqlInt64 number => Encode(number.Value),
            SqlSingle number => Encode(number.Value),
            SqlDouble number => Encode(number.Value),
            SqlMoney number => Encode(number.Value),
            SqlDateTime date => Encode(date.Value),
            SqlGuid guid => Encode(guid.Value),
            _ => throw new UnsupportedValueException()
        };
    }
}

public static class ReaderMapper
{
    /// <summary>Reads actual cells and result boundaries, retaining empty sets and duplicate names.</summary>
    public static async Task<List<ResultSet>> ReadAsync(DbDataReader reader, CancellationToken cancellationToken,
        List<ResultSet>? results = null)
    {
        results ??= new();
        do {
            if (reader.FieldCount == 0) continue;
            var result = new ResultSet();
            for (var column = 0; column < reader.FieldCount; column++)
                result.Columns.Add(new(reader.GetName(column), reader.GetDataTypeName(column)));
            while (await reader.ReadAsync(cancellationToken)) {
                var row = new string?[reader.FieldCount];
                for (var column = 0; column < reader.FieldCount; column++) {
                    // SqlDecimal handles decimal(38,...) without overflowing CLR decimal.
                    object value;
                    if (reader is SqlDataReader sql) value = sql.GetSqlValue(column);
                    else if (reader is MySqlDataReader mysql && reader.GetDataTypeName(column).Equals("DECIMAL", StringComparison.OrdinalIgnoreCase) && !reader.IsDBNull(column))
                        value = mysql.GetMySqlDecimal(column);
                    else value = reader.GetValue(column);
                    row[column] = ValueEncoder.Encode(value);
                }
                result.Rows.Add(row);
            }
            results.Add(result);
        } while (await reader.NextResultAsync(cancellationToken));
        return results;
    }
}
