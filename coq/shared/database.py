from collections import Counter
from sqlite3.dbapi2 import Connection

from std2.sqllite3 import add_functions, escape


def _like_esc(like: str) -> str:
    escaped = escape(nono={"%", "_", "["}, escape="!", param=like)
    return f"{escaped}%"


def _similarity(lhs: str, rhs: str) -> float:
    l_c, r_c = Counter(lhs), Counter(rhs)
    dif = l_c - r_c if len(lhs) > len(rhs) else r_c - l_c
    bigger, smaller = max(len(lhs), len(rhs)), min(len(lhs), len(rhs))
    ratio = 1 - sum(dif.values()) / bigger
    adjust = smaller / bigger
    return ratio / adjust


def init_db(conn: Connection) -> None:
    add_functions(conn)
    conn.create_function("X_LIKE_ESC", narg=1, func=_like_esc, deterministic=True)
    conn.create_function("X_SIMILARITY", narg=2, func=_similarity, deterministic=True)

