from contextlib import suppress
from itertools import islice
from locale import strxfrm
from os import linesep, sep
from os.path import normcase
from pathlib import Path, PurePath
from typing import Iterator, Optional

from std2.asyncio import run_in_executor

from ..lang import LANG
from ..shared.types import Doc

_KB = 1000
_HOME = Path.home()


def show_path(cwd: PurePath, path: PurePath, is_dir: bool) -> str:
    posfix = sep if is_dir else ""
    with suppress(ValueError):
        rel = path.relative_to(cwd)
        return f".{sep}{normcase(rel)}{posfix}"

    with suppress(ValueError):
        rel = path.relative_to(_HOME)
        return f"~{sep}{normcase(rel)}{posfix}"

    return f"{normcase(path)}{posfix}"


async def _show_dir(cwd: PurePath, path: Path, ellipsis: str, height: int) -> Doc:
    def lines() -> Iterator[str]:
        ordered = sorted(path.iterdir(), key=lambda p: strxfrm(str(p)))
        for idx, child in enumerate(islice(ordered, height), start=1):
            if idx >= height and len(ordered) > height:
                yield ellipsis
            else:
                yield show_path(cwd, path=child, is_dir=child.is_dir())

    def cont() -> Doc:
        text = linesep.join(lines())
        doc = Doc(text=text, syntax="")
        return doc

    return await run_in_executor(cont)


async def _show_file(path: Path, ellipsis: str, height: int) -> Doc:
    def lines() -> Iterator[str]:
        with path.open("r") as fd:
            lines = fd.readlines(_KB)
        lit = islice((line.rstrip() for line in lines), height)
        for idx, line in enumerate(lit, start=1):
            if idx >= height and len(lines) > height:
                yield ellipsis
            else:
                yield line

    def cont() -> Doc:
        try:
            text = linesep.join(lines())
        except UnicodeDecodeError:
            text = LANG("file binary")

        t = text or LANG("file empty")
        doc = Doc(text=t, syntax="")
        return doc

    return await run_in_executor(cont)


async def show(cwd: PurePath, path: Path, ellipsis: str, height: int) -> Optional[Doc]:
    try:
        if path.is_dir():
            return await _show_dir(cwd, path=path, ellipsis=ellipsis, height=height)
        elif path.is_file():
            return await _show_file(path, ellipsis=ellipsis, height=height)
        else:
            return None
    except (FileNotFoundError, PermissionError):
        return None
