from functools import cache
from math import nan
from pathlib import Path
from sqlite3.dbapi2 import Connection
from typing import Any, MutableSequence, Optional, Protocol, cast

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


class _Quantile:
    def __init__(self) -> None:
        self._q = nan
        self._acc: MutableSequence[float] = []

    def step(self, value: Optional[float], q: float) -> None:
        assert q >= 0 and q <= 1
        self._q = q
        if value is not None:
            self._acc.append(value)

    def finalize(self) -> Optional[float]:
        ordered = sorted(self._acc)
        if not ordered:
            return None
        else:
            idx = round((len(ordered) - 1) * self._q)
            return ordered[idx]


def init_db(conn: Connection) -> None:
    add_functions(conn)
    conn.create_function("X_LIKE_ESC", narg=1, func=_like_esc, deterministic=True)
    conn.create_function("X_SIMILARITY", narg=2, func=similarity, deterministic=True)
    conn.create_aggregate("X_QUANTILE", n_arg=2, aggregate_class=cast(Any, _Quantile))

