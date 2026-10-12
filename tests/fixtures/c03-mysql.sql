-- Read-only live C03 check. No tables, credentials or data writes required.
SELECT
  CONVERT(CONCAT('  pipe|tab', CHAR(9), 'line', CHAR(13), CHAR(10), '雪  ') USING utf8mb4) AS same,
  CAST(NULL AS CHAR) AS same,
  '' AS empty_value,
  'NULL' AS literal_null,
  REPEAT('x', 10000) AS long_value,
  CAST(123456789012345678901234567890.123456789 AS DECIMAL(60,9)) AS precise_value,
  UNHEX('000AFF') AS binary_value;
SELECT 'empty set' AS empty_header WHERE 1 = 0;
SELECT 'second set' AS value;
