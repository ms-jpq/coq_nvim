from asyncio import Queue
from asyncio.locks import Event
from dataclasses import dataclass
from itertools import chain
from os import linesep
from typing import AsyncIterator, Dict, Iterator, Sequence, Set

from pynvim import Nvim
from pynvim.api.buffer import Buffer
from pynvim.api.common import NvimError

from .pkgs.fc_types import Completion, Context, Seed, Source
from .pkgs.nvim import autocmd, call, run_forever
from .pkgs.scheduler import schedule
from .pkgs.shared import coalesce, find_matches, normalize


@dataclass(frozen=True)
class Config:
    polling_rate: float
    min_length: int
    max_length: int


def buf_gen(nvim: Nvim, bufnrs: Set[int]) -> Iterator[Buffer]:
    if bufnrs:
        seen: Set[str] = set()
        buffers: Sequence[Buffer] = nvim.api.list_bufs()
        for buf in buffers:
            if buf.number in bufnrs:
                filename = nvim.api.buf_get_name(buf)
                if filename not in seen:
                    seen.add(filename)
                    yield buf


async def buffer_chars(nvim: Nvim, buf_gen: Iterator[Buffer]) -> Sequence[str]:
    def cont() -> Sequence[str]:
        lines = tuple(
            line
            for buffer in buf_gen
            for line in nvim.api.buf_get_lines(buffer, 0, -1, True)
        )
        return lines

    try:
        lines = await call(nvim, cont)
    except NvimError:
        return ()
    else:
        chars = tuple(char for line in lines for char in chain(line, linesep))
        return chars


async def main(nvim: Nvim, chan: Queue, seed: Seed) -> Source:
    config = Config(**seed.config)
    ch = Event()
    min_length, max_length = config.min_length, config.max_length

    bufnrs: Set[int] = set()
    words: Dict[str, str] = {}

    await autocmd(
        nvim,
        name="buffers",
        events=("TextChanged", "TextChangedI", "BufEnter"),
        arg_eval=("'add'", "expand('<abuf>')",),
    )

    async def ooda() -> None:
        while True:
            action, bufnr = await chan.get()
            if action == "add":
                bufnrs.add(bufnr)
            elif action == "clear":
                words.clear()

    async def background_update() -> None:
        async for _ in schedule(ch, min_time=0.0, max_time=config.polling_rate):
            b_gen = buf_gen(nvim, bufnrs)
            bufnrs.clear()
            chars = await buffer_chars(nvim, b_gen)
            for word in coalesce(chars, min_length=min_length, max_length=max_length):
                if word not in words:
                    words[word] = normalize(word)

    async def source(context: Context) -> AsyncIterator[Completion]:
        position = context.position
        old_prefix, old_suffix = context.alnums_before, context.alnums_after
        cword, ncword = context.alnums, context.alnums_normalized

        for word in find_matches(
            cword, ncword=ncword, min_match=min_length, words=words
        ):
            yield Completion(
                position=position,
                old_prefix=old_prefix,
                new_prefix=word,
                old_suffix=old_suffix,
                new_suffix="",
            )

    run_forever(nvim, ooda)
    run_forever(nvim, background_update)
    return source
