from difflib import SequenceMatcher
from sqlite3.dbapi2 import Connection

from std2.sqllite3 import add_functions


def _similarity(lhs: str, rhs: str) -> float:
    m = SequenceMatcher(a=lhs, b=rhs, isjunk=None)
    return m.ratio()


def init_db(conn: Connection) -> None:
    add_functions(conn)
    conn.create_function("X_SIMILARITY", narg=2, func=_similarity, deterministic=True)

