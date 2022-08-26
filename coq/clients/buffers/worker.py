from contextlib import suppress
from os import linesep
from pathlib import PurePath
from typing import AsyncIterator, Iterator, Mapping

from pynvim.api.buffer import Buffer
from pynvim.api.common import NvimError
from pynvim_pp.api import buf_change_tick, list_bufs
from pynvim_pp.lib import async_call, go
from pynvim_pp.logging import with_suppress

from ...databases.buffers.database import BDB, BufferWord
from ...paths.show import fmt_path
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BuffersClient
from ...shared.types import Completion, Context, Doc, Edit


def _doc(client: BuffersClient, context: Context, word: BufferWord) -> Doc:
    def cont() -> Iterator[str]:
        if not client.same_filetype and word.filetype:
            yield f"{word.filetype}{client.parent_scope}"

        path = PurePath(word.filename)
        pos = fmt_path(
            context.cwd, path=path, is_dir=False, current=PurePath(context.filename)
        )
        yield f"{pos}:{word.line_num}"

    return Doc(text=linesep.join(cont()), syntax="")


class Worker(BaseWorker[BuffersClient, BDB]):
    def __init__(
        self, supervisor: Supervisor, options: BuffersClient, misc: BDB
    ) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        go(supervisor.nvim, aw=self._poll())

    async def _poll(self) -> None:
        def c1() -> Mapping[Buffer, int]:
            bufs = {
                buf: buf_change_tick(self._supervisor.nvim, buf=buf)
                for buf in list_bufs(self._supervisor.nvim, listed=True)
            }
            return bufs

        while True:
            with with_suppress():
                with suppress(NvimError):
                    bufs = await async_call(self._supervisor.nvim, c1)
                    dead = await self._misc.vacuum(
                        {buf.number: change_tick for buf, change_tick in bufs.items()}
                    )

                    def c2() -> None:
                        buffers = {buf.number: buf for buf in bufs}
                        for buf_id in dead:
                            if buf := buffers.get(buf_id):
                                with suppress(NvimError):
                                    self._supervisor.nvim.api.buf_detach(buf)

                    await async_call(self._supervisor.nvim, c2)
                async with self._supervisor.idling:
                    await self._supervisor.idling.wait()

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        async with self._work_lock:
            filetype = context.filetype if self.options.same_filetype else None
            words = await self._misc.words(
                self._supervisor.match,
                filetype=filetype,
                word=context.words,
                sym=context.syms if self.options.match_syms else "",
                limitless=context.manual,
            )
            for word in words:
                edit = Edit(new_text=word.text)
                cmp = Completion(
                    source=self.options.short_name,
                    always_on_top=self.options.always_on_top,
                    weight_adjust=self.options.weight_adjust,
                    label=edit.new_text,
                    sort_by=word.text,
                    primary_edit=edit,
                    adjust_indent=False,
                    doc=_doc(self.options, context=context, word=word),
                    icon_match="Text",
                )
                yield cmp
