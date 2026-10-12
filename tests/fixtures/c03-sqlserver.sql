-- Read-only live C03 check. No tables, credentials or data writes required.
SELECT
  N'  pipe|tab' + NCHAR(9) + N'line' + NCHAR(13) + NCHAR(10) + N'雪  ' AS same,
  CAST(NULL AS nvarchar(20)) AS same,
  CAST(N'' AS nvarchar(20)) AS empty_value,
  N'NULL' AS literal_null,
  REPLICATE(CAST(N'x' AS nvarchar(max)), 10000) AS long_value,
  CAST(123456789012345678901234567890.12345678 AS decimal(38,8)) AS precise_value,
  CAST(0x000AFF AS varbinary(max)) AS binary_value;
SELECT N'empty set' AS empty_header WHERE 1 = 0;
SELECT N'second set' AS value;
