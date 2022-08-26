from contextlib import suppress
from dataclasses import dataclass
from os import linesep
from pathlib import PurePath
from typing import AsyncIterator, Iterator, Mapping, Optional, Sequence, Tuple

from pynvim.api import Buffer, Nvim
from pynvim.api.common import NvimError
from pynvim_pp.api import (
    buf_filetype,
    buf_get_lines,
    buf_line_count,
    buf_name,
    cur_win,
    list_bufs,
    win_get_buf,
    win_get_cursor,
)
from pynvim_pp.lib import async_call, go
from pynvim_pp.logging import with_suppress

from ...databases.buffers.database import BDB, BufferWord
from ...paths.show import fmt_path
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BuffersClient
from ...shared.types import Completion, Context, Doc, Edit


@dataclass(frozen=True)
class _Info:
    buf_id: int
    filetype: str
    filename: str
    range: Tuple[int, int]
    lines: Sequence[str]
    buffers: Mapping[Buffer, int]


def _info(nvim: Nvim) -> Optional[_Info]:
    try:
        win = cur_win(nvim)
        height: int = nvim.api.win_get_height(win)
        buf = win_get_buf(nvim, win=win)
        bufs = list_bufs(nvim, listed=True)
        buffers = {buf: buf_line_count(nvim, buf=buf) for buf in bufs}
        if (current_lines := buffers.get(buf)) is None:
            return None
        else:
            row, _ = win_get_cursor(nvim, win=win)
            lo = max(0, row - height)
            hi = min(current_lines, row + height + 1)
            lines = buf_get_lines(nvim, buf=buf, lo=lo, hi=hi)
            filetype = buf_filetype(nvim, buf=buf)
            filename = buf_name(nvim, buf=buf)
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
        go(supervisor.nvim, aw=self._poll())

    async def _poll(self) -> None:
        nvim = self._supervisor.nvim

        while True:
            with with_suppress():
                if info := await async_call(nvim, _info, nvim):
                    lo, hi = info.range
                    buf_line_counts = {
                        buf.number: line_count
                        for buf, line_count in info.buffers.items()
                    }
                    dead = await self._misc.vacuum(buf_line_counts)
                    await self.set_lines(
                        info.buf_id,
                        filetype=info.filetype,
                        filename=info.filename,
                        lo=lo,
                        hi=hi,
                        lines=info.lines,
                    )

                    bufs = {buf.number: buf for buf in info.buffers}

                    def rm_dead() -> None:
                        for buf_id in dead:
                            if buf := bufs.get(buf_id):
                                with suppress(NvimError):
                                    nvim.api.buf_detach(buf)

                    await async_call(nvim, rm_dead)

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
            words = await self._misc.words(
                self._supervisor.match,
                filetype=filetype,
                word=context.words,
                sym=context.syms if self._options.match_syms else "",
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
                    doc=_doc(self._options, context=context, word=word),
                    icon_match="Text",
                )
                yield cmp
