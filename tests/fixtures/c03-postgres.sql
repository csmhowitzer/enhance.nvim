-- Read-only live C03 check. No tables, credentials or data writes required.
SELECT
  '  pipe|tab' || chr(9) || 'line' || chr(13) || chr(10) || '雪  ' AS same,
  NULL::text AS same,
  ''::text AS empty_value,
  'NULL'::text AS literal_null,
  repeat('x', 10000) AS long_value,
  123456789012345678901234567890.123456789::numeric AS precise_value,
  decode('000aff', 'hex') AS binary_value;
SELECT 'empty set' AS empty_header WHERE false;
SELECT 'second set' AS value;
