from asyncio import Queue, get_running_loop
from os import listdir
from os.path import dirname, isdir, sep
from typing import AsyncIterator, Iterator, Sequence
from pathlib import Path

from pynvim import Nvim

from ..shared.types import Completion, Context, Seed, Source

NAME = "paths"


def parse_path(root: str, parent: str = "") -> str:
    def cont() -> Iterator[str]:
        l, s, r = root.rpartition(sep)
        if s == sep:
            curr = f"{s}{r}{parent}"
            yield from parse_path(l, parent=curr)
            if sep not in l:
                if l.endswith(".."):
                    yield ".." + curr
                elif l.endswith("."):
                    yield "." + curr
                elif l.endswith("~"):
                    yield str(Path.home()) + curr
            yield curr

    return "".join(cont())


def list_dir(path: str) -> Sequence[str]:
    try:
        return listdir(path)
    except PermissionError:
        return ()


async def find_children(path: str, context: Context) -> Sequence[Completion]:
    position = context.position
    old_prefix, old_suffix = context.alnums_before, context.alnums_after
    loop = get_running_loop()

    def cont() -> Iterator[Completion]:
        parent = dirname(path)
        if isdir(path):
            end = "" if path.endswith(sep) else sep
            for child in list_dir(path):
                text = end + child
                yield Completion(
                    position=position,
                    old_prefix=old_prefix,
                    new_prefix=text,
                    old_suffix=old_suffix,
                    new_suffix="",
                    label=text,
                )
        elif isdir(parent):
            for child in list_dir(parent):
                yield Completion(
                    position=position,
                    old_prefix=old_prefix,
                    new_prefix=child,
                    old_suffix=old_suffix,
                    new_suffix="",
                )

    def co() -> Sequence[Completion]:
        return tuple(cont())

    return await loop.run_in_executor(None, co)


async def main(nvim: Nvim, chan: Queue, seed: Seed) -> Source:
    async def source(context: Context) -> AsyncIterator[Completion]:
        before = context.line_before
        path = parse_path(before)
        for child in await find_children(path, context):
            yield child

    return source
