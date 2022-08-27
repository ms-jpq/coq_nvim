from os import linesep
from pathlib import PurePath
from typing import AsyncIterator, Iterator, Mapping, Optional, Tuple

from pynvim import Nvim
from pynvim_pp.api import buf_line_count, list_bufs
from pynvim_pp.lib import async_call, go
from pynvim_pp.logging import with_suppress

from ...databases.treesitter.database import TDB
from ...paths.show import fmt_path
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import TSClient
from ...shared.types import Completion, Context, Doc, Edit
from ...treesitter.request import async_request
from ...treesitter.types import Payload


def _bufs(nvim: Nvim) -> Mapping[int, int]:
    bufs = {
        buf.number: buf_line_count(nvim, buf=buf)
        for buf in list_bufs(nvim, listed=True)
    }
    return bufs


def _doc(client: TSClient, context: Context, payload: Payload) -> Optional[Doc]:
    def cont() -> Iterator[str]:
        clhs, crhs = context.comment

        path = PurePath(context.filename)
        pos = fmt_path(
            context.cwd, path=PurePath(payload.filename), is_dir=False, current=path
        )

        yield clhs
        yield pos
        yield ":"
        if range := payload.range:
            lo, hi = range
            yield str(lo)
            if hi != lo:
                yield "-"
                yield str(hi)
        yield client.path_sep
        yield crhs
        yield linesep

        if payload.grandparent:
            yield clhs
            yield payload.grandparent.kind
            yield linesep
            yield payload.grandparent.text
            yield crhs

        if payload.grandparent and payload.parent:
            yield linesep
            yield clhs
            yield client.path_sep
            yield crhs
            yield linesep

        if payload.parent:
            yield clhs
            yield payload.parent.kind
            yield linesep
            yield payload.parent.text
            yield crhs

    doc = Doc(syntax=context.filetype, text="".join(cont()))
    return doc


def _trans(client: TSClient, context: Context, payload: Payload) -> Completion:
    edit = Edit(new_text=payload.text)
    icon_match, _, _ = payload.kind.partition(".")
    cmp = Completion(
        source=client.short_name,
        always_on_top=client.always_on_top,
        weight_adjust=client.weight_adjust,
        label=edit.new_text,
        sort_by=payload.text,
        primary_edit=edit,
        adjust_indent=False,
        kind=payload.kind,
        doc=_doc(client, context=context, payload=payload),
        icon_match=icon_match,
    )
    return cmp


class Worker(BaseWorker[TSClient, TDB]):
    def __init__(self, supervisor: Supervisor, options: TSClient, misc: TDB) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        go(supervisor.nvim, aw=self._poll())

    async def _poll(self) -> None:
        while True:
            with with_suppress():
                bufs = await async_call(
                    self._supervisor.nvim, _bufs, self._supervisor.nvim
                )
                await self._misc.vacuum(bufs)
                async with self._supervisor.idling:
                    await self._supervisor.idling.wait()

    async def populate(self) -> Optional[Tuple[bool, float]]:
        if payload := await async_request(self._supervisor.nvim):
            keep_going = payload.elapsed <= self._options.slow_threshold
            await self._misc.populate(
                payload.buf,
                lo=payload.lo,
                hi=payload.hi,
                filetype=payload.filetype,
                filename=payload.filename,
                nodes=payload.payloads,
            )
            return keep_going, payload.elapsed
        else:
            return None

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        async with self._work_lock:
            payloads = await self._misc.select(
                self._supervisor.match,
                filetype=context.filetype,
                word=context.words,
                sym=context.syms,
                limitless=context.manual,
            )

            for payload in payloads:
                yield _trans(self._options, context=context, payload=payload)
