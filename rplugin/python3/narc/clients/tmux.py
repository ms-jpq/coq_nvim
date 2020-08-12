from asyncio import Lock, as_completed, gather
from asyncio.locks import Event
from dataclasses import dataclass
from os import linesep
from shutil import which
from typing import AsyncIterator, Iterator, Sequence, Set

from ..shared.da import call
from ..shared.nvim import run_forever
from ..shared.parse import coalesce, parse_common_affix
from ..shared.sql import AConnection
from ..shared.types import Comm, Completion, Context, MEdit, Seed, Source
from .pkgs.scheduler import schedule
from .pkgs.sql import init, populate, prefix_query

NAME = "tmux"


@dataclass(frozen=True)
class Config:
    polling_rate: float
    prefix_matches: int
    max_length: int


class TmuxError(Exception):
    pass


@dataclass(frozen=True)
class TmuxPane:
    session_id: str
    pane_id: str
    pane_active: bool
    window_active: bool


async def tmux_session() -> str:
    ret = await call("tmux", "display-message", "-p", "#{session_id}")
    if ret.code != 0:
        raise TmuxError(ret.err)
    else:
        return ret.out.strip()


async def tmux_panes() -> Sequence[TmuxPane]:
    ret = await call(
        "tmux",
        "list-panes",
        "-a",
        "-F",
        "#{session_id} #{pane_id} #{pane_active} #{window_active}",
    )

    def cont() -> Iterator[TmuxPane]:
        for line in ret.out.splitlines():
            session_id, pane_id, pane_active, window_active = line.split(" ")
            info = TmuxPane(
                session_id=session_id,
                pane_id=pane_id,
                pane_active=bool(int(pane_active)),
                window_active=bool(int(window_active)),
            )
            yield info

    if ret.code != 0:
        raise TmuxError(ret.err)
    else:
        return tuple(cont())


async def screenshot(pane: TmuxPane) -> str:
    ret = await call("tmux", "capture-pane", "-p", "-t", pane.pane_id)
    if ret.code != 0:
        raise TmuxError(ret.err)
    else:
        return ret.out


def is_active(session_id: str, pane: TmuxPane) -> bool:
    return session_id == pane.session_id and pane.pane_active and pane.window_active


async def tmux_words(
    max_length: int, unifying_chars: Set[str]
) -> AsyncIterator[Iterator[str]]:
    if which("tmux"):
        session_id, panes = await gather(tmux_session(), tmux_panes())
        sources = tuple(
            screenshot(pane) for pane in panes if not is_active(session_id, pane=pane)
        )
        for source in as_completed(sources):
            text = await source
            it = iter(text)
            words = coalesce(it, max_length=max_length, unifying_chars=unifying_chars)
            yield words


async def main(comm: Comm, seed: Seed) -> Source:
    nvim, log = comm.nvim, comm.log
    config = Config(**seed.config)
    prefix_matches, max_length, unifying_chars = (
        config.prefix_matches,
        config.max_length,
        seed.match.unifying_chars,
    )

    conn, lock = AConnection(), Lock()
    async with lock:
        await init(conn)

    async def background_update() -> None:
        async for _ in schedule(Event(), min_time=0, max_time=config.polling_rate):
            async with lock:
                await init(conn)
            try:
                async for words in tmux_words(
                    max_length=max_length, unifying_chars=unifying_chars
                ):
                    async with lock:
                        await populate(conn, words=words)
            except TmuxError as e:
                message = f"failed to fetch tmux{linesep}{e}"
                log.warn("%s", message)

    async def source(context: Context) -> AsyncIterator[Completion]:
        position, ncword = context.position, context.alnums_normalized

        async with lock:
            async for word, match_normalized in prefix_query(
                conn, ncword=ncword, prefix_matches=prefix_matches
            ):
                old_prefix, old_suffix = parse_common_affix(
                    context, match_normalized=match_normalized, use_line=False,
                )

                medit = MEdit(
                    old_prefix=old_prefix,
                    new_prefix=word,
                    old_suffix=old_suffix,
                    new_suffix="",
                )
                yield Completion(position=position, medit=medit)

    run_forever(nvim, log=log, thing=background_update)
    return source
