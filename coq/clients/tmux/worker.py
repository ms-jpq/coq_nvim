from os import linesep
from pathlib import Path
from typing import AsyncIterator, Iterator, Tuple

from pynvim_pp.lib import go
from pynvim_pp.logging import with_suppress

from ...databases.tmux.database import TMDB, TmuxWord
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import TmuxClient
from ...shared.timeit import timeit
from ...shared.types import Completion, Context, Doc, Edit
from ...tmux.parse import snapshot


def _doc(client: TmuxClient, word: TmuxWord) -> Doc:
    def cont() -> Iterator[str]:
        if client.all_sessions:
            yield f"S: {word.session_name}{client.parent_scope}"
        yield f"W: #{word.window_index}{client.path_sep}{word.window_name}{client.parent_scope}"
        yield f"P: #{word.pane_index}{client.path_sep}{word.pane_title}"

    return Doc(text=linesep.join(cont()), syntax="")


class Worker(BaseWorker[TmuxClient, TMDB]):
    def __init__(
        self, supervisor: Supervisor, options: TmuxClient, misc: Tuple[Path, TMDB]
    ) -> None:
        self._exec, db = misc
        super().__init__(supervisor, options=options, misc=db)
        go(supervisor.nvim, aw=self._poll())

    async def _poll(self) -> None:
        while True:
            with with_suppress():
                with timeit("IDLE :: TMUX"):
                    await self.periodical()

                async with self._supervisor.idling:
                    await self._supervisor.idling.wait()

    async def periodical(self) -> None:
        current, panes = await snapshot(
            self._exec, all_sessions=self._options.all_sessions
        )
        await self._misc.periodical(current, panes=panes)

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        async with self._work_lock:
            words = await self._misc.select(
                self._supervisor.match,
                word=context.words,
                sym=(context.syms if self._options.match_syms else ""),
                limitless=context.manual,
            )

            for word in words:
                edit = Edit(new_text=word.text)
                cmp = Completion(
                    source=self._options.short_name,
                    always_on_top=self._options.always_on_top,
                    weight_adjust=self._options.weight_adjust,
                    label=edit.new_text,
                    sort_by=word.text,
                    primary_edit=edit,
                    adjust_indent=False,
                    doc=_doc(self._options, word=word),
                    icon_match="Text",
                )
                yield cmp
