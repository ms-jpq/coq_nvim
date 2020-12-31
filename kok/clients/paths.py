from itertools import accumulate
from os import listdir
from os.path import curdir, dirname, isdir, join, realpath, sep
from pathlib import Path
from typing import Any, Iterator, Sequence

from pynvim import Nvim

from ..shared.chan import Chan
from ..shared.comm import make_ch
from ..shared.core import run_forever
from ..shared.da import run_in_executor
from ..shared.types import (
    Channel,
    ChannelClosed,
    Completion,
    Context,
    SEdit,
    Seed,
    SourceChans,
)

NAME = "paths"


def parse_dots(path: str) -> str:
    def cont() -> Iterator[str]:
        for c in reversed(path):
            if c == curdir:
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

    return await run_in_executor(co)


async def main(nvim: Nvim, seed: Seed) -> SourceChans:
    send_ch, recv_ch = make_ch(Context, Channel[Completion])

    async def ooda() -> None:
        async for uid, context in send_ch:
            async with Chan[Completion]() as ch:
                await recv_ch.send((uid, ch))

                pos, before = context.position, context.line_before
                _, _, old_prefix = before.rpartition(sep)
                paths = parse_paths(before)
                prefix_char = next(iter(old_prefix), "")

                for child in await find_children(paths):
                    if child.startswith(prefix_char):
                        sedit = SEdit(new_text=child)
                        comp = Completion(position=pos, sedit=sedit)
                        try:
                            await ch.send(comp)
                        except ChannelClosed:
                            break

    run_forever(ooda)
    return SourceChans(comm_ch=Chan[Any](), send_ch=send_ch, recv_ch=recv_ch)
