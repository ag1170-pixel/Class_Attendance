"""SQLite data layer (stdlib only — no install needed).

Prototype store that implements the documented schema. Swapping to Postgres +
pgvector in production changes only this module; the service layer above is
unchanged.
"""
from __future__ import annotations

import sqlite3
import struct
import uuid
from pathlib import Path
from typing import List, Optional

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_DB = BASE_DIR / "attendance.db"
SCHEMA = BASE_DIR / "schema.sql"


def new_id() -> str:
    return uuid.uuid4().hex


# ── embedding (de)serialization: float32[] <-> BLOB ─────────────────────────
def pack_embedding(values: List[float]) -> bytes:
    return struct.pack(f"<{len(values)}f", *values)


def unpack_embedding(blob: bytes) -> List[float]:
    n = len(blob) // 4
    return list(struct.unpack(f"<{n}f", blob))


class Database:
    def __init__(self, path: Optional[Path] = None):
        self.path = str(path or DEFAULT_DB)
        self._conn = sqlite3.connect(self.path)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA foreign_keys = ON;")

    def init_schema(self) -> None:
        with open(SCHEMA) as f:
            self._conn.executescript(f.read())
        self._conn.commit()

    @property
    def conn(self) -> sqlite3.Connection:
        return self._conn

    def execute(self, sql: str, params: tuple = ()) -> sqlite3.Cursor:
        cur = self._conn.execute(sql, params)
        self._conn.commit()
        return cur

    def query(self, sql: str, params: tuple = ()) -> List[sqlite3.Row]:
        return list(self._conn.execute(sql, params).fetchall())

    def query_one(self, sql: str, params: tuple = ()) -> Optional[sqlite3.Row]:
        return self._conn.execute(sql, params).fetchone()

    def close(self) -> None:
        self._conn.close()
