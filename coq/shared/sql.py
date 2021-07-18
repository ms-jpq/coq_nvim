from functools import cache
from pathlib import Path
from sqlite3.dbapi2 import Connection
from statistics import median
from typing import Any, MutableSequence, Protocol, cast

from std2.pathlib import AnyPath
from std2.sqllite3 import add_functions, escape

from .parse import similarity

BIGGEST_INT = 2 ** 63 - 1


class _Loader(Protocol):
    def __call__(self, *paths: AnyPath) -> str:
        ...


def loader(base: Path) -> _Loader:
    def cont(*paths: AnyPath) -> str:
        path = (base / Path(*paths)).with_suffix(".sql")
        return path.read_text("UTF-8")

    return cast(_Loader, cache(cont))


def _like_esc(like: str) -> str:
    escaped = escape(nono={"%", "_", "["}, escape="!", param=like)
    return f"{escaped}%"


class _Median:
    def __init__(self) -> None:
        self._acc: MutableSequence[float] = []

    def step(self, value: float) -> None:
        self._acc.append(value)

    def finalize(self) -> float:
        return median(self._acc)


def init_db(conn: Connection) -> None:
    add_functions(conn)
    conn.create_function("X_LIKE_ESC", narg=1, func=_like_esc, deterministic=True)
    conn.create_function("X_SIMILARITY", narg=2, func=similarity, deterministic=True)
    conn.create_aggregate("X_MEDIAN", n_arg=1, aggregate_class=cast(Any, _Median))

