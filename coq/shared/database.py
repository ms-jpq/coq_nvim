from difflib import SequenceMatcher
from sqlite3.dbapi2 import Connection

from std2.sqllite3 import add_functions, escape


def _like_esc(like: str) -> str:
    escaped = escape(nono={"%", "_", "["}, escape="!", param=like)
    return f"{escaped}%"


def _similarity(lhs: str, rhs: str) -> float:
    m = SequenceMatcher(a=lhs, b=rhs[: len(lhs)], isjunk=None)
    return m.quick_ratio()


def init_db(conn: Connection) -> None:
    add_functions(conn)
    conn.create_function("X_LIKE_ESC", narg=1, func=_like_esc, deterministic=True)
    conn.create_function("X_SIMILARITY", narg=2, func=_similarity, deterministic=True)

