from asyncio import Queue, get_running_loop
from os import listdir
from os.path import dirname, isdir, sep
from typing import AsyncIterator, Iterator, Sequence

from pynvim import Nvim

from ..shared.da import anext
from ..shared.types import Completion, Context, Seed, Source

NAME = "paths"


def parse_path(root: str, parent: str = "") -> Iterator[str]:
    l, s, r = root.rpartition(sep)
    if s == sep:
        curr = f"{s}{r}{parent}"
        yield from parse_path(l, parent=curr)
        if sep not in l:
            if l.endswith(".."):
                yield ".." + curr
            elif l.endswith("."):
                yield "." + curr
        yield curr


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
        else:
            return

    def co() -> Sequence[Completion]:
        return tuple(cont())

    return await loop.run_in_executor(None, co)


async def main(nvim: Nvim, chan: Queue, seed: Seed) -> Source:
    async def source(context: Context) -> AsyncIterator[Completion]:
        before = context.line_before

        async def next_children() -> AsyncIterator[Sequence[Completion]]:
            for path in parse_path(before):
                children = await find_children(path, context=context)
                yield children

        co = await anext(next_children())
        for c in co or ():
            yield c

    return source
