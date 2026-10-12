"""Database-free child process fixture for the asynchronous Lua runner tests."""
import json
import sys
import time

request = json.load(sys.stdin)  # Requires the parent to close stdin through EOF.
query = request["query"]
if query == "__hang__":
    time.sleep(30)
sys.stderr.write("secret-password: fixture diagnostics must not escape\n")
json.dump({
    "protocol": 1,
    "ok": True,
    "resultSets": [{
        "columns": [{"name": "query", "type": "nvarchar"},
                    {"name": "null", "type": "varchar"}],
        "rows": [[query, None]],
    }],
    "messages": [],
    "errors": [],
    "affectedRows": None,
    "durationMs": 1,
}, sys.stdout, ensure_ascii=False)
sys.stdout.write("\n")
