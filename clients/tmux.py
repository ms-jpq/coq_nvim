from asyncio import Queue
from dataclasses import dataclass
from typing import AsyncIterator, Iterator, Sequence

from pynvim import Nvim

from .pkgs.da import call
from .pkgs.fc_types import Source, SourceCompletion, SourceFeed, SourceSeed


class TmuxError(Exception):
    pass


@dataclass(frozen=True)
class PaneInfo:
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


async def tmux_panes() -> Sequence[PaneInfo]:
    ret = await call(
        "tmux",
        "list-panes",
        "-a",
        "-f",
        "#{session_id} #{pane_id} #{pane_active} #{window_active}",
    )

    def cont() -> Iterator[PaneInfo]:
        for line in ret.out.splitlines():
            session_id, pane_id, pane_active, window_active = line.split(" ")
            info = PaneInfo(
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


async def tmux_pane_words(pane_id: str) -> str:
    ret = await call("tmux", "capture-pane", "-p", "-t", pane_id)
    if ret.code != 0:
        raise TmuxError(ret.err)
    else:
        return ret.out


async def context() -> None:
    # await call("tmux")
    pass


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        yield SourceCompletion(
            position=feed.position,
            old_prefix="",
            new_prefix="",
            old_suffix="",
            new_suffix="",
        )

    return source
