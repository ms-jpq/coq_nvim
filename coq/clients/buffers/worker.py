from asyncio import create_task
from dataclasses import dataclass
from os import linesep
from pathlib import PurePath
from typing import AsyncIterator, Iterator, Mapping, Optional, Sequence, Tuple

from pynvim_pp.buffer import Buffer
from pynvim_pp.logging import suppress_and_log
from pynvim_pp.rpc_types import NvimError
from pynvim_pp.window import Window

from ...paths.show import fmt_path
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BuffersClient
from ...shared.types import Completion, Context, Doc, Edit
from .db.database import BDB, BufferWord, Update


@dataclass(frozen=True)
class _Info:
    buf_id: int
    filetype: str
    filename: str
    range: Tuple[int, int]
    lines: Sequence[str]
    buffers: Mapping[Buffer, int]


async def _info() -> Optional[_Info]:
    try:
        win = await Window.get_current()
        height = await win.get_height()
        buf = await win.get_buf()
        bufs = await Buffer.list(listed=True)
        buffers = {buf: await buf.line_count() for buf in bufs}
        if (current_lines := buffers.get(buf)) is None:
            return None
        else:
            row, _ = await win.get_cursor()
            lo = max(0, row - height)
            hi = min(current_lines, row + height + 1)
            lines = await buf.get_lines(lo=lo, hi=hi)
            filetype = await buf.filetype()
            filename = (await buf.get_name()) or ""
            info = _Info(
                buf_id=buf.number,
                filetype=filetype,
                filename=filename,
                range=(lo, hi),
                lines=lines,
                buffers=buffers,
            )
            return info
    except NvimError:
        return None


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
        create_task(self._poll())

    async def _poll(self) -> None:
        while True:
            with suppress_and_log():
                if info := await _info():
                    lo, hi = info.range
                    buf_line_counts = {
                        int(buf.number): line_count
                        for buf, line_count in info.buffers.items()
                    }
                    await self._misc.vacuum(buf_line_counts)
                    await self.set_lines(
                        info.buf_id,
                        filetype=info.filetype,
                        filename=info.filename,
                        lo=lo,
                        hi=hi,
                        lines=info.lines,
                    )

                async with self._supervisor.idling:
                    await self._supervisor.idling.wait()

    async def buf_update(self, buf_id: int, filetype: str, filename: str) -> None:
        await self._misc.buf_update(buf_id, filetype=filetype, filename=filename)

    async def set_lines(
        self,
        buf_id: int,
        filetype: str,
        filename: str,
        lo: int,
        hi: int,
        lines: Sequence[str],
    ) -> None:
        await self._misc.set_lines(
            buf_id,
            filetype=filetype,
            filename=filename,
            lo=lo,
            hi=hi,
            lines=lines,
        )

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        async with self._work_lock:
            filetype = context.filetype if self._options.same_filetype else None
            update = (
                Update(
                    buf_id=context.buf_id,
                    filetype=context.filetype,
                    filename=context.filename,
                    lo=change.range.start,
                    hi=change.range.stop,
                    lines=change.lines,
                )
                if (change := context.change)
                else None
            )
            words = await self._misc.words(
                self._supervisor.match,
                filetype=filetype,
                word=context.words,
                sym=context.syms if self._options.match_syms else "",
                limitless=context.manual,
                update=update,
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
                    doc=_doc(self._options, context=context, word=word),
                    icon_match="Text",
                )
                yield cmp
