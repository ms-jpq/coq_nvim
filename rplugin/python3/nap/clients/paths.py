from asyncio import Queue, get_running_loop
from itertools import accumulate
from os import listdir
from os.path import dirname, isdir, sep
from pathlib import Path
from typing import AsyncIterator, Iterator, Sequence

from pynvim import Nvim

from ..shared.types import Completion, Context, Seed, Source

NAME = "paths"


def parse_dots(path: str) -> str:
    def cont() -> Iterator[str]:
        for c in reversed(path):
            if c == ".":
                yield c
            else:
                break

    return "".join(cont())


def parse_paths(root: str) -> Iterator[str]:
    home = str(Path.home())

    def cont(root: str) -> Iterator[str]:
        lhs, s, rhs = root.rpartition(sep)
        if s:
            yield f"{sep}{rhs}"
            yield from cont(lhs)
        else:
            if rhs.endswith("~"):
                yield home
            else:
                dots = parse_dots(rhs)
                if dots:
                    yield dots

    def combine(a: str, b: str) -> str:
        return b + a

    return reversed(tuple(accumulate(cont(root), func=combine)))


async def find_children(paths: Iterator[str], context: Context) -> Sequence[Completion]:
    position = context.position
    old_prefix, old_suffix = context.alnums_before, context.alnums_after
    loop = get_running_loop()

    def cont() -> Iterator[Completion]:
        for path in paths:
            parent = dirname(path)
            try:
                if isdir(path):
                    end = "" if path.endswith(sep) else sep
                    for child in listdir(path):
                        text = end + child
                        yield Completion(
                            position=position,
                            old_prefix=old_prefix,
                            new_prefix=text,
                            old_suffix=old_suffix,
                            new_suffix="",
                            label=text,
                        )
                    break
                elif isdir(parent):
                    for child in listdir(parent):
                        yield Completion(
                            position=position,
                            old_prefix=old_prefix,
                            new_prefix=child,
                            old_suffix=old_suffix,
                            new_suffix="",
                        )
                    break
            except PermissionError:
                pass

    def co() -> Sequence[Completion]:
        return tuple(cont())

    return await loop.run_in_executor(None, co)


async def main(nvim: Nvim, chan: Queue, seed: Seed) -> Source:
    async def source(context: Context) -> AsyncIterator[Completion]:
        before = context.line_before
        paths = parse_paths(before)
        for child in await find_children(paths, context):
            yield child

    return source
