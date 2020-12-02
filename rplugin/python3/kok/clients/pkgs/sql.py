from asyncio import Lock, QueueFull
from dataclasses import dataclass, field
from os.path import dirname, join, realpath
from typing import Iterable, Iterator, Tuple
from uuid import UUID, uuid4

from ...shared.chan import Chan, Channel
from ...shared.core import run_forever, run_forevers
from ...shared.da import slurp
from ...shared.sql import SQL_TYPES, AConnection, sql_escape
from ...shared.types import Context

__sql__ = join(realpath(dirname(__file__)), "sql")

_PRAGMA = slurp(join(__sql__, "pragma.sql"))
_INIT = slurp(join(__sql__, "init.sql"))
_DEPOPULATE = slurp(join(__sql__, "depopulate.sql"))
_POPULATE = slurp(join(__sql__, "populate.sql"))
_QUERY = slurp(join(__sql__, "query.sql"))


ESCAPE_CHAR = "!"
LIKE_ESCAPE = {"_", "[", "%"} | {ESCAPE_CHAR}


@dataclass(frozen=True)
class QueryParams:
    context: Context
    prefix_matches: int
    uuid: UUID = field(default_factory=uuid4)


@dataclass(frozen=True)
class DBChans:
    depop_ch: Channel[None]
    pop_ch: Channel[Iterator[str]]
    ask_ch: Channel[QueryParams]
    reply_ch: Channel[Tuple[UUID, Channel[str]]]


async def db() -> DBChans:
    depop_ch, pop_ch, ask_ch, reply_ch = (
        Chan[None](),
        Chan[Iterator[str]](),
        Chan[QueryParams](),
        Chan[Tuple[UUID, Channel[str]]](),
    )
    conn, lock = AConnection(), Lock()

    async with await conn.execute_script(_PRAGMA):
        pass
    async with await conn.execute_script(_INIT):
        pass

    async def depop() -> None:
        async for _ in depop_ch:
            async with lock:
                async with await conn.execute_script(_DEPOPULATE):
                    pass

    async def pop() -> None:
        async for words in pop_ch:

            def cont() -> Iterator[Iterable[SQL_TYPES]]:
                for word in words:
                    yield word, word

            async with lock:
                async with await conn.execute_many(_POPULATE, cont()):
                    pass
                await conn.commit()

    async def ask() -> None:
        async for param in ask_ch:
            ch = Chan[str]()

            async def reply() -> None:
                context, prefix_matches = param.context, param.prefix_matches
                cword, ncword = context.alnums, context.alnums_normalized
                prefix = ncword[:prefix_matches]
                escaped = sql_escape(prefix, nono=LIKE_ESCAPE, escape=ESCAPE_CHAR)
                match = f"{escaped}%" if escaped else ""

                async with lock:
                    async with await conn.execute(_QUERY, (match, cword)) as cursor:
                        async for row in cursor:
                            try:
                                await ch.send(row["word"])
                            except QueueFull:
                                break

            run_forever(reply)
            await reply_ch.send((param.uuid, ch))

    run_forevers(depop, pop, ask)

    return DBChans(depop_ch=depop_ch, pop_ch=pop_ch, ask_ch=ask_ch, reply_ch=reply_ch)
