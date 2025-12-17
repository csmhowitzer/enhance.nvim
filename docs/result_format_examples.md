# Result Format Examples

This document contains examples of raw query output from different database types.
Used for reference when implementing result parsing and formatting.

## SQL Server (sqlcmd)

### SELECT Query with Results

```
COLUMN_NAME|DATA_TYPE|CHARACTER_MAXIMUM_LENGTH|IS_NULLABLE
-----------|---------|------------------------|-----------
Id|bigint|NULL|NO
CompanyId|uniqueidentifier|NULL|NO
ConnectionId|uniqueidentifier|NULL|NO
Key|nvarchar|200|NO
Value|nvarchar|-1|YES
LastModified|datetime2|NULL|NO
Deleted|bit|NULL|NO
(7 rows affected)

Query completed in 368.64ms
Database: AcculynxDB-Dev
```

**Observations:**
- Line 1: Column headers (pipe-separated)
- Line 2: Separator line (dashes and pipes)
- Lines 3-9: Data rows (7 rows)
- Line 10: `(7 rows affected)` - row count message
- Lines 11-12: Current footer (execution time, database name)

**Row Count Logic:**
- Total lines: 12
- Header rows: 2 (line 1-2)
- Data rows: 7 (line 3-9)
- Footer: 3 (line 10-12)
- Parse: `(7 rows affected)` → extract `7`

### INSERT/UPDATE/DELETE Query

```
(5 rows affected)

Query completed in 45.23ms
Database: AcculynxDB-Dev
```

**Observations:**
- Line 1: `(X rows affected)` message
- Lines 2-3: Current footer

**Row Count Logic:**
- Parse: `(5 rows affected)` → extract `5` or use full message

---

## SQLite (sqlite3)

### SELECT Query with Results

```
cid  name         type     notnull  dflt_value  pk
---  -----------  -------  -------  ----------  --
0    ID           INTEGER  0                    1 
1    Name         TEXT     1                    0 
2    Description  TEXT     0                    0 
3    CreatedDate  TEXT     1                    0 

Query completed in 17.61ms
Database: example.db
```

**Observations:**
- Line 1: Column headers (space-separated, aligned)
- Line 2: Separator line (dashes)
- Lines 3-6: Data rows (4 rows)
- Line 7: Empty line
- Lines 8-9: Current footer (execution time, database name)

**Row Count Logic:**
- Total lines: 9
- Header rows: 2 (line 1-2)
- Data rows: 4 (line 3-6)
- Empty line: 1 (line 7)
- Footer: 2 (line 8-9)
- Count: Total lines - header (2) - empty lines - footer (2) = 4 rows

### INSERT/UPDATE/DELETE Query

```
-- SQLite doesn't output row count by default
-- Need to check if there's a way to get this info

Query completed in 5.12ms
Database: example.db
```

**Row Count Logic:**
- SQLite may not provide explicit row count for DML operations
- May need to use `changes()` function or parse differently

---

## MySQL (mysql)

### SELECT Query

```
+----+-------+
| id | name  |
+----+-------+
|  1 | Alice |
|  2 | Bob   |
+----+-------+
2 rows in set (0.01 sec)
```

**Observations:**
- ASCII table format with borders
- Footer shows: `X rows in set (Y sec)`

**Row Count Logic:**
- Parse: `2 rows in set` → extract `2`

### INSERT/UPDATE/DELETE Query

```
Query OK, 5 rows affected (0.01 sec)
```

**Row Count Logic:**
- Parse: `5 rows affected` → extract `5`

---

## PostgreSQL (psql)

### SELECT Query

```
 id | name  
----+-------
  1 | Alice
  2 | Bob
(2 rows)
```

**Observations:**
- Simple table format
- Footer shows: `(X rows)`

**Row Count Logic:**
- Parse: `(2 rows)` → extract `2`

### INSERT/UPDATE/DELETE Query

```
INSERT 0 5
```

**Row Count Logic:**
- Parse: `INSERT 0 5` → extract `5` (third token)
- Format: `COMMAND OID COUNT`

---

## Parsing Strategy

### Row Count Detection

**Priority order:**
1. **Explicit row count message** (SQL Server, MySQL, PostgreSQL)
   - SQL Server: `(X rows affected)`
   - MySQL: `X rows affected` or `X rows in set`
   - PostgreSQL: `(X rows)` or `INSERT/UPDATE/DELETE 0 X`

2. **Count data rows** (SQLite, fallback for others)
   - Skip first 2 lines (headers)
   - Skip empty lines
   - Skip footer lines (our added metadata)
   - Count remaining lines

### Current Footer Format

**Lines added by executor:**
```
Query completed in X.XXms
Database: <connection_name>
```

**New Status Line Format (to replace footer):**
```
─────────────────────────────────────────────────────────────
Connection: <name> | Type: <db_type> | Rows: <count> | Time: <ms> | Executed: <timestamp>
─────────────────────────────────────────────────────────────
```

