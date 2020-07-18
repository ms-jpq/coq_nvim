from asyncio import Queue, get_running_loop
from os import listdir
from os.path import dirname, isdir, sep
from typing import AsyncIterator, Iterator, Sequence

from pkgs.da import anext
from pkgs.types import Source, SourceCompletion, SourceFeed, SourceSeed
from pynvim import Nvim


def parse_path(root: str, parent: str = "") -> Iterator[str]:
    l, s, r = root.rpartition(sep)
    if s == sep:
        curr = f"{s}{r}{parent}"
        yield from parse_path(l, parent=curr)
        yield curr


async def find_children(path: str) -> Sequence[str]:
    loop = get_running_loop()

    def cont() -> None:
        parent = dirname(path)
        if isdir(path):
            return listdir(path)
        elif isdir(parent):
            return listdir(parent)
        else:
            return ()

    return await loop.run_in_executor(None, cont)


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        col = feed.position.col
        before = feed.line[:col]
        paths_coll = (await find_children(nvim, path) for path in parse_path(before))
        paths = await anext(paths_coll, ())
        for path in paths:
            pl = len(path)
            text = path[pl:]
            yield SourceCompletion(text=text, label=path)

    return source
