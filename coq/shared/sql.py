from functools import lru_cache
from os.path import normcase
from pathlib import Path
from sqlite3.dbapi2 import Connection
from typing import Protocol, cast

from pynvim_pp.lib import decode
from std2.pathlib import AnyPath
from std2.sqlite3 import add_functions, escape

from .fuzzy import quick_ratio

BIGGEST_INT = 2**63 - 1


class _Loader(Protocol):
    def __call__(self, *paths: AnyPath) -> str:
        ...


def loader(base: Path) -> _Loader:
    @lru_cache(maxsize=None)
    def cont(*paths: AnyPath) -> str:
        path = (base / Path(*paths)).with_suffix(".sql")
        return decode(path.read_bytes())

    return cast(_Loader, cont)


@lru_cache
def like_esc(like: str) -> str:
    escaped = escape(nono={"%", "_", "["}, escape="!", param=like)
    return f"{escaped}%"


def init_db(conn: Connection) -> None:
    add_functions(conn)
    conn.create_function("X_SIMILARITY", narg=3, func=quick_ratio, deterministic=True)
    conn.create_function("X_NORM_CASE", narg=1, func=normcase, deterministic=True)
