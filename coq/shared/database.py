from locale import strcoll
from sqlite3.dbapi2 import Connection, Row

from std2.sqllite3 import escape

from .parse import lower, normalize


def _like_esc(like: str) -> str:
    escaped = escape(nono={"%", "_"}, escape="!", param=like)
    return f"{escaped}%"


def init_db(conn: Connection) -> None:
    conn.row_factory = Row
    conn.create_collation("X_COLL", strcoll)
    conn.create_function("X_LOWER", narg=1, func=lower, deterministic=True)
    conn.create_function("X_NORM", narg=1, func=normalize, deterministic=True)
    conn.create_function("X_LIKE_ESC", narg=1, func=_like_esc, deterministic=True)

