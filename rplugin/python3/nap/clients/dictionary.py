from asyncio import Queue
from dataclasses import dataclass
from sqlite3 import connect
from typing import AsyncIterator

from pynvim import Nvim

from ..shared.types import Completion, Context, Seed, Source

NAME = "dictionary"


@dataclass(frozen=True)
class Config:
    pass


async def main(nvim: Nvim, chan: Queue, seed: Seed) -> Source:
    db = connect(":memory:", check_same_thread=False, isolation_level=None)

    async def source(context: Context) -> AsyncIterator[Completion]:
        yield Completion(
            position=context.position,
            old_prefix="",
            new_prefix="",
            old_suffix="",
            new_suffix="",
        )

    return source
