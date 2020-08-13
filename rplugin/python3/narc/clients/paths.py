from itertools import accumulate
from os import listdir
from os.path import dirname, isdir, join, realpath, sep
from pathlib import Path
from typing import AsyncIterator, Iterator, Sequence

from ..shared.da import run_in_executor
from ..shared.types import Comm, Completion, Context, MEdit, Seed, Source

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

    it = reversed(tuple(accumulate(cont(root), func=combine)))
    for p in it:
        dots = parse_dots(p)
        if p != dots:
            yield p


def list_dir(path: str) -> Iterator[str]:
    for p in listdir(path):
        if isdir(join(path, p)):
            yield p + sep
        else:
            yield p


async def find_children(paths: Iterator[str]) -> Sequence[str]:
    def cont() -> Iterator[str]:
        for path in paths:
            rp = realpath(path)
            parent = dirname(rp)
            try:
                if isdir(path):
                    end = "" if path.endswith(sep) or path.endswith(".") else sep
                    for child in list_dir(rp):
                        text = end + child
                        yield text
                    break
                elif isdir(parent):
                    yield from list_dir(parent)
                    break
            except PermissionError:
                pass

    def co() -> Sequence[str]:
        return tuple(cont())

    return await run_in_executor(None, co)


async def main(comm: Comm, seed: Seed) -> Source:
    async def source(context: Context) -> AsyncIterator[Completion]:
        position = context.position
        before = context.line_before
        _, _, old_prefix = before.rpartition(sep)
        paths = parse_paths(before)

        prefix_char = next(iter(old_prefix), "")
        for child in await find_children(paths):
            if child.startswith(prefix_char):
                medit = MEdit(
                    old_prefix=old_prefix,
                    new_prefix=child,
                    old_suffix="",
                    new_suffix="",
                )
                yield Completion(position=position, medit=medit)

    return source
