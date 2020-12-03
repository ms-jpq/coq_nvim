from asyncio import Lock
from dataclasses import dataclass
from os.path import dirname, join, realpath
from typing import Iterable, Iterator, Tuple

from ...shared.chan import Chan, Channel
from ...shared.comm import make_ch
from ...shared.core import run_forever
from ...shared.da import slurp
from ...shared.sql import SQL_TYPES, AConnection, sql_escape
from ...shared.types import ChannelClosed, Context

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


@dataclass(frozen=True)
class DBChans:
    depop_ch: Channel[None]
    pop_ch: Channel[Iterator[str]]
    ask_ch: Channel[Tuple[int, QueryParams]]
    reply_ch: Channel[Tuple[int, Channel[str]]]


async def new_db() -> DBChans:
    depop_ch, pop_ch = Chan[None](), Chan[Iterator[str]]()
    ask_ch, reply_ch = make_ch(QueryParams, Channel[str])

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
        async for uid, param in ask_ch:
            async with Chan[str]() as ch:
                await reply_ch.send((uid, ch))

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
                            except ChannelClosed:
                                break

    run_forever(depop, pop, ask)

    return DBChans(depop_ch=depop_ch, pop_ch=pop_ch, ask_ch=ask_ch, reply_ch=reply_ch)
