from os import linesep
from typing import AsyncIterator, Iterator, Optional

from pynvim_pp.api import list_bufs
from pynvim_pp.lib import async_call, go

from ...databases.treesitter.database import TDB
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import TSClient
from ...shared.types import Completion, Context, Doc, Edit
from ...treesitter.types import Payload


def _doc(client: TSClient, context: Context, payload: Payload) -> Optional[Doc]:
    def cont() -> Iterator[str]:
        clhs, crhs = context.comment

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
        weight_adjust=client.weight_adjust,
        label=edit.new_text,
        sort_by=payload.text,
        primary_edit=edit,
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
            bufs = await async_call(
                self._supervisor.nvim,
                lambda: list_bufs(self._supervisor.nvim, listed=True),
            )
            await self._misc.vacuum({buf.number for buf in bufs})
            async with self._supervisor.idling:
                await self._supervisor.idling.wait()

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        payloads = await self._misc.select(
            self._supervisor.match,
            buf_id=context.buf_id,
            word=context.words,
            sym=context.syms,
            limitless=context.manual,
        )

        for payload in payloads:
            yield _trans(self._options, context=context, payload=payload)
