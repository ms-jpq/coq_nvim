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


async def find_children(path: str, feed: SourceFeed) -> Sequence[SourceCompletion]:
    position = feed.position
    old_prefix = feed.prefix.alnums
    loop = get_running_loop()
    partial_name = basename(path)

    def cont() -> Iterator[SourceCompletion]:
        parent = dirname(path)
        if isdir(path):
            end = "" if path.endswith(sep) else sep
            for child in list_dir(path):
                text = end + child
                yield SourceCompletion(
                    position=position,
                    old_prefix=old_prefix,
                    new_prefix=text,
                    label=text,
                )
        elif isdir(parent):
            for child in list_dir(parent):
                if child.startswith(partial_name):
                    yield SourceCompletion(
                        position=position, old_prefix=old_prefix, new_prefix=child
                    )
        else:
            return

    def co() -> Sequence[SourceCompletion]:
        return tuple(cont())

    return await loop.run_in_executor(None, co)


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        col = feed.position.col
        before = feed.prefix.line[:col]
        comp = (await find_children(path, feed=feed) for path in parse_path(before))
        co = await anext(comp, ())
        for c in co:
            yield c

    return source
