from functools import cache
from pathlib import Path
from typing import Protocol, cast

from std2.pathlib import AnyPath


class _Loader(Protocol):
    def __call__(self, *paths: AnyPath) -> str:
        ...


def loader(base: Path) -> _Loader:
    def cont(*paths: AnyPath) -> str:
        path = base / Path(*paths)
        return path.read_text("UTF-8")

    return cast(_Loader, cache(cont))

