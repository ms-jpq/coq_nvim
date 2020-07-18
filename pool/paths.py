from asyncio import Queue, get_running_loop
from os import listdir
from os.path import isdir, sep
from typing import AsyncIterator, Iterator, Sequence

from pkgs.da import anext
from pkgs.types import Source, SourceCompletion, SourceFeed, SourceSeed
from pkgs.nvim import print
from pynvim import Nvim


def parse_path(root: str, parent: str = "") -> Iterator[str]:
    l, s, r = root.rpartition(sep)
    if s == sep:
        curr = f"{s}{r}{parent}"
        if l.endswith("."):
            yield "." + curr
        else:
            yield from parse_path(l, parent=curr)
            yield curr


async def find_children(path: str) -> Sequence[str]:
    loop = get_running_loop()

    def cont() -> None:
        if isdir(path):
            return listdir(path)
        else:
            return ()

    return await loop.run_in_executor(None, cont)


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    loop = get_running_loop()

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        col = feed.position.col
        before = feed.line[col:]
        paths = (
            path
            for path in parse_path(before)
            if await loop.run_in_executor(None, isdir, path)
        )
        path = await anext(paths, None)
        await print(nvim, before)
        await print(nvim, [*parse_path(before)])
        if path:
            pl = len(path)
            children = await loop.run_in_executor(None, listdir, path)
            for child in children:
                text = child[pl:]
                yield SourceCompletion(text=text, label=child)

    return source
