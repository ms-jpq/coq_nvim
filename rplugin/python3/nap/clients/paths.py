from asyncio import get_running_loop
from itertools import accumulate
from os import listdir
from os.path import dirname, isdir, join, realpath, sep
from pathlib import Path
from typing import AsyncIterator, Iterator, Sequence

from ..shared.match import gen_metric
from ..shared.parse import normalize
from ..shared.types import Comm, Completion, Context, Seed, Source

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


def list_dir(path: str) -> Iterator[str]:
    for p in listdir(path):
        if isdir(join(path, p)):
            yield p + sep
        else:
            yield p


async def find_children(paths: Iterator[str]) -> Sequence[str]:
    loop = get_running_loop()

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

    return await loop.run_in_executor(None, co)


async def main(comm: Comm, seed: Seed) -> Source:
    async def source(context: Context) -> AsyncIterator[Completion]:
        position = context.position
        before = context.line_before
        _, _, old_prefix = before.rpartition(sep)
        paths = parse_paths(before)

        for child in await find_children(paths):
            metric = gen_metric(
                old_prefix,
                ncword=normalize(old_prefix),
                match=child,
                n_match=normalize(child),
                options=seed.match,
                use_secondary=False,
            )
            if not old_prefix or metric.num_matches:
                yield Completion(
                    position=position,
                    old_prefix=old_prefix,
                    new_prefix=child,
                    old_suffix="",
                    new_suffix="",
                    label="",
                )

    return source
