"""SQLite persistence for migration run results."""

import datetime
import pathlib
import sqlite3

DB_PATH = pathlib.Path(__file__).parent.parent / "data" / "mainframe_reinvent.db"

FIELDS = [
    "functional_spec",
    "dependency_map",
    "test_cases",
    "java_code",
    "python_code",
    "equivalence_review",
    "refinement_log",
    "model_used",
    "python_tests",
    "python_test_results",
    "test_execution_status",
    "python_wrapper",
    "java_wrapper",
    "wrapper_status",
]


def get_connection():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_connection()
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS results (
            filename TEXT NOT NULL,
            backend TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            {', '.join(f'{f} TEXT' for f in FIELDS)},
            updated_at TEXT,
            PRIMARY KEY (filename, backend)
        )
        """
    )
    existing_cols = {row["name"] for row in conn.execute("PRAGMA table_info(results)")}
    for field in FIELDS:
        if field not in existing_cols:
            conn.execute(f"ALTER TABLE results ADD COLUMN {field} TEXT")

    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS spans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL,
            backend TEXT NOT NULL,
            trace_id TEXT NOT NULL,
            span_id TEXT NOT NULL,
            parent_span_id TEXT,
            name TEXT NOT NULL,
            start_time REAL NOT NULL,
            end_time REAL NOT NULL,
            duration_ms REAL NOT NULL,
            status TEXT NOT NULL,
            attributes TEXT
        )
        """
    )
    conn.commit()
    conn.close()


def insert_span(**fields):
    conn = get_connection()
    columns = list(fields.keys())
    placeholders = ", ".join("?" for _ in columns)
    conn.execute(
        f"INSERT INTO spans ({', '.join(columns)}) VALUES ({placeholders})",
        [fields[c] for c in columns],
    )
    conn.commit()
    conn.close()


def get_spans(filename: str, backend: str | None = None):
    conn = get_connection()
    if backend:
        rows = conn.execute(
            "SELECT * FROM spans WHERE filename = ? AND backend = ? ORDER BY start_time",
            (filename, backend),
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM spans WHERE filename = ? ORDER BY start_time", (filename,)
        ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def clear_spans(filename: str, backend: str):
    conn = get_connection()
    conn.execute("DELETE FROM spans WHERE filename = ? AND backend = ?", (filename, backend))
    conn.commit()
    conn.close()


def upsert_result(filename: str, backend: str, status: str, **fields):
    conn = get_connection()
    now = datetime.datetime.utcnow().isoformat()
    existing = conn.execute(
        "SELECT 1 FROM results WHERE filename = ? AND backend = ?",
        (filename, backend),
    ).fetchone()

    if existing:
        set_clauses = ["status = ?", "updated_at = ?"]
        values = [status, now]
        for key, value in fields.items():
            if key in FIELDS:
                set_clauses.append(f"{key} = ?")
                values.append(value)
        values += [filename, backend]
        conn.execute(
            f"UPDATE results SET {', '.join(set_clauses)} "
            f"WHERE filename = ? AND backend = ?",
            values,
        )
    else:
        columns = ["filename", "backend", "status", "updated_at"] + [
            k for k in fields if k in FIELDS
        ]
        values = [filename, backend, status, now] + [
            fields[k] for k in fields if k in FIELDS
        ]
        placeholders = ", ".join("?" for _ in columns)
        conn.execute(
            f"INSERT INTO results ({', '.join(columns)}) VALUES ({placeholders})",
            values,
        )
    conn.commit()
    conn.close()


def get_result(filename: str, backend: str):
    conn = get_connection()
    row = conn.execute(
        "SELECT * FROM results WHERE filename = ? AND backend = ?",
        (filename, backend),
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def get_all_results(filename: str):
    conn = get_connection()
    rows = conn.execute(
        "SELECT * FROM results WHERE filename = ?", (filename,)
    ).fetchall()
    conn.close()
    return {row["backend"]: dict(row) for row in rows}
