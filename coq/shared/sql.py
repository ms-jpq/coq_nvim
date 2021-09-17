from functools import lru_cache
from json import dumps
from os.path import normcase
from pathlib import Path
from sqlite3.dbapi2 import Connection
from typing import (
    AbstractSet,
    Any,
    Callable,
    Iterator,
    MutableSequence,
    MutableSet,
    Optional,
    Protocol,
    Tuple,
    cast,
)

from std2.pathlib import AnyPath
from std2.sqlite3 import add_functions, escape

from .fuzzy import quick_ratio
from .parse import is_word

BIGGEST_INT = 2 ** 63 - 1


class _Loader(Protocol):
    def __call__(self, *paths: AnyPath) -> str:
        ...


def loader(base: Path) -> _Loader:
    @lru_cache(maxsize=None)
    def cont(*paths: AnyPath) -> str:
        path = (base / Path(*paths)).with_suffix(".sql")
        return path.read_text("UTF-8")

    return cast(_Loader, cont)


def _like_esc(like: str) -> str:
    escaped = escape(nono={"%", "_", "["}, escape="!", param=like)
    return f"{escaped}%"


class _Quantiles:
    def __init__(self) -> None:
        self._qs: MutableSet[float] = set()
        self._acc: MutableSequence[float] = []

    def step(self, value: Optional[float], *quantiles: float) -> None:
        for q in quantiles:
            self._qs.add(q)

        if value is not None:
            self._acc.append(value)

    def finalize(self) -> str:
        def cont() -> Iterator[Tuple[int, Optional[float]]]:
            ordered = sorted(self._acc)
            for q in self._qs:
                assert q >= 0 and q <= 1
                key = round(q * 100)
                if ordered:
                    idx = round((len(ordered) - 1) * q)
                    yield key, ordered[idx]
                else:
                    yield key, None

        acc = {f"q{key}": val for key, val in cont()}
        json = dumps(acc, check_circular=False, ensure_ascii=False)
        return json


def _word_start(
    unifying_chars: AbstractSet[str],
) -> Callable[[Optional[str]], Optional[bool]]:

    def cont(word: Optional[str]) -> Optional[bool]:
        if word is None:
            return None
        else:
            return is_word(word[:1], unifying_chars=unifying_chars)

    return cont


def init_db(conn: Connection, unifying_chars: AbstractSet[str]) -> None:
    add_functions(conn)
    conn.create_function(
        "X_WORD_START", narg=1, func=_word_start(unifying_chars), deterministic=True
    )
    conn.create_function("X_LIKE_ESC", narg=1, func=_like_esc, deterministic=True)
    conn.create_function("X_SIMILARITY", narg=3, func=quick_ratio, deterministic=True)
    conn.create_function("X_NORM_CASE", narg=1, func=normcase, deterministic=True)
    conn.create_aggregate(
        "X_QUANTILES", n_arg=-1, aggregate_class=cast(Any, _Quantiles)
    )
