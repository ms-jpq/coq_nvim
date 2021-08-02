from itertools import islice
from locale import strxfrm
from os import linesep, sep
from pathlib import Path, PurePath
from typing import Iterator, Optional

from std2.asyncio import run_in_executor

from ..lang import LANG
from ..shared.types import Doc

_KB = 1000


async def _show_dir(path: Path, ellipsis: str, height: int) -> Doc:
    def lines() -> Iterator[str]:
        ordered = sorted(path.iterdir(), key=lambda p: strxfrm(str(p)))
        for idx, child in enumerate(islice(ordered, height), start=1):
            if idx >= height and len(ordered) > height:
                yield ellipsis
            else:
                if child.is_dir():
                    yield f"{child}{sep}"
                else:
                    yield str(child)

    def cont() -> Doc:
        text = linesep.join(lines())
        doc = Doc(text=text, syntax="")
        return doc

    return await run_in_executor(cont)


async def _show_file(path: Path, ellipsis: str, height: int) -> Doc:
    def lines() -> Iterator[str]:
        with path.open("r") as fd:
            lines = fd.readlines(_KB)
        for idx, line in enumerate(islice(lines, height), start=1):
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


async def show(cwd:PurePath,path: Path, ellipsis: str, height: int) -> Optional[Doc]:
    try:
        if path.is_dir():
            return await _show_dir(path, ellipsis=ellipsis, height=height)
        elif path.is_file():
            return await _show_file(path, ellipsis=ellipsis, height=height)
        else:
            return None
    except (FileNotFoundError, PermissionError):
        return None
