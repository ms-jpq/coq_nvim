from asyncio import QueueFull, as_completed, gather
from dataclasses import dataclass
from os import linesep
from shutil import which
from typing import Any, AsyncIterator, Iterator, Sequence, Set

from pynvim import Nvim

from ..shared.chan import Chan
from ..shared.comm import make_ch, schedule
from ..shared.core import run_forever
from ..shared.da import call, tiktok
from ..shared.logging import log
from ..shared.parse import coalesce
from ..shared.types import (
    Channel,
    Completion,
    Context,
    SEdit,
    Seed,
    Source,
    SourceChans,
)
from .pkgs.sql import QueryParams, new_db

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


async def main(nvim: Nvim, seed: Seed) -> Source:
    send_ch, recv_ch = make_ch(Context, Channel[Completion])

    config = Config(**seed.config)

    db = await new_db()
    req = schedule(ask=db.ask_ch, reply=db.reply_ch)

    async def background_update() -> None:
        async for _ in tiktok(config.polling_rate):
            await db.depop_ch.send(None)
            try:
                async for words in tmux_words(
                    max_length=config.max_length,
                    unifying_chars=seed.match.unifying_chars,
                ):
                    await db.pop_ch.send(words)
            except TmuxError as e:
                message = f"failed to fetch tmux{linesep}{e}"
                log.warn("%s", message)

    async def ooda() -> None:
        async for uid, context in send_ch:
            async with Chan[Completion]() as ch:
                await recv_ch.send((uid, ch))

                params = QueryParams(
                    context=context, prefix_matches=config.prefix_matches
                )
                async with await req(params) as resp:
                    async for word in resp:
                        sedit = SEdit(new_text=word)
                        comp = Completion(position=context.position, sedit=sedit)
                        try:
                            await ch.send(comp)
                        except QueueFull:
                            break

    run_forever(background_update, ooda)
    return SourceChans(comm_ch=Chan[Any](), send_ch=send_ch, recv_ch=recv_ch)
