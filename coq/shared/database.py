from collections import Counter
from sqlite3.dbapi2 import Connection

from std2.sqllite3 import add_functions, escape


def _like_esc(like: str) -> str:
    escaped = escape(nono={"%", "_", "["}, escape="!", param=like)
    return f"{escaped}%"


def _similarity(lhs: str, rhs: str) -> float:
    l, r = Counter(lhs), Counter(rhs)
    a = l - r if len(lhs) > len(rhs) else r - l
    t = sum(a.values())
    m = max(len(lhs), len(rhs))
    return t / m


def init_db(conn: Connection) -> None:
    add_functions(conn)
    conn.create_function("X_LIKE_ESC", narg=1, func=_like_esc, deterministic=True)
    conn.create_function("X_SIMILARITY", narg=2, func=_similarity, deterministic=True)

