from asyncio import Queue, get_running_loop
from os import listdir
from os.path import basename, dirname, isdir, sep
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


def list_dir(path: str) -> Sequence[str]:
    try:
        return listdir(path)
    except PermissionError:
        return ()


async def find_children(path: str) -> Sequence[SourceCompletion]:
    loop = get_running_loop()

    def cont() -> Iterator[SourceCompletion]:
        parent = dirname(path)
        partial_name = basename(path)
        if isdir(path):
            end = "" if path.endswith(sep) else sep
            for child in list_dir(path):
                text = end + child
                yield SourceCompletion(text=text, label=text)
        elif isdir(parent):
            partial_name = basename(path)
            pl = len(partial_name)
            for child in list_dir(parent):
                if child.startswith(partial_name) and child != partial_name:
                    text = child[pl:]
                    yield SourceCompletion(text=text, label=child)
        else:
            return

    def co() -> Sequence[SourceCompletion]:
        return tuple(cont())

    return await loop.run_in_executor(None, co)


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        col = feed.position.col
        before = feed.line[:col]
        comp = (await find_children(path) for path in parse_path(before))
        co = await anext(comp, ())
        for c in co:
            yield c

    return source
