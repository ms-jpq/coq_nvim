from pathlib import PurePath
from textwrap import dedent
from typing import NoReturn

from ..types import LoadError


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
