from asyncio import Queue, as_completed, gather
from asyncio.locks import Event
from dataclasses import dataclass
from shutil import which
from typing import AsyncIterator, Dict, Iterator, Sequence

from pynvim import Nvim

from ..shared.da import call
from ..shared.parse import coalesce, find_matches, normalize
from ..shared.types import Completion, Context, Seed, Source
from ..shared.nvim import print, run_forever
from .pkgs.scheduler import schedule


NAME = "tmux"


@dataclass(frozen=True)
class Config:
    polling_rate: float
    min_length: int
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


async def tmux_words(min_length: int, max_length: int) -> AsyncIterator[str]:
    if which("tmux"):
        session_id, panes = await gather(tmux_session(), tmux_panes())
        sources = tuple(
            screenshot(pane) for pane in panes if not is_active(session_id, pane=pane)
        )
        for source in as_completed(sources):
            text = await source
            it = iter(text)
            for word in coalesce(it, min_length=min_length, max_length=max_length):
                yield word


async def main(nvim: Nvim, chan: Queue, seed: Seed) -> Source:
    config = Config(**seed.config)
    min_length, max_length = config.min_length, config.max_length
    words: Dict[str, str] = {}

    async def background_update() -> None:
        async for _ in schedule(Event(), min_time=0, max_time=config.polling_rate):
            words.clear()
            try:
                async for word in tmux_words(
                    min_length=min_length, max_length=max_length
                ):
                    if word not in words:
                        words[word] = normalize(word)
            except TmuxError as e:
                await print(nvim, e)

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

    run_forever(nvim, background_update)
    return source
