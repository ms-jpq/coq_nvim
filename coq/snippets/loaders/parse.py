from pathlib import PurePath
from textwrap import dedent
from typing import Iterable, Iterator, NoReturn, Set

from ..types import LoadError, Options

_OPTIONS_MAP = {o.name: o for o in Options}


def raise_err(path: PurePath, lineno: int, line: str, reason: str) -> NoReturn:
    msg = f"""\
    Cannot load:
    path:   {path}
    lineno: {lineno}
    line:   {line}
    reason: |-
    {reason}
    """
    raise LoadError(dedent(msg))


def opt_parse(opts: Iterable[str]) -> Set[Options]:
    def cont() -> Iterator[Options]:
        for c in opts:
            opt = _OPTIONS_MAP.get(c.strip())
            if opt:
                yield opt
            else:
                pass

    return {*cont()}

