from os import linesep
from typing import AsyncIterator, Iterator, Optional

from pynvim_pp.lib import go

from ...databases.treesitter.database import TDB
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context, Doc, Edit
from ...treesitter.types import Payload


def _doc(syntax: str, payload: Payload) -> Optional[Doc]:
    def cont() -> Iterator[str]:
        if payload.grandparent:
            yield payload.grandparent.kind
            yield " -> "
            yield payload.grandparent.text

        if payload.grandparent and payload.parent:
            yield linesep

        if payload.parent:
            yield payload.parent.kind
            yield " -> "
            yield payload.parent.text

    doc = Doc(syntax=syntax, text="".join(cont()))
    return doc


def _trans(client: BaseClient, syntax: str, payload: Payload) -> Completion:
    edit = Edit(new_text=payload.text)
    cmp = Completion(
        source=client.short_name,
        weight_adjust=client.weight_adjust,
        label=edit.new_text,
        sort_by=payload.text,
        primary_edit=edit,
        kind=payload.kind,
        doc=_doc(syntax, payload=payload),
    )
    return cmp


class Worker(BaseWorker[BaseClient, TDB]):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: TDB) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        go(supervisor.nvim, aw=self._poll())

    async def _poll(self) -> None:
        while True:
            pass

            async with self._supervisor.idling:
                await self._supervisor.idling.wait()

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        match = context.words or context.syms
        payloads = await self._misc.select(
            self._supervisor.options, word=match, limitless=context.manual
        )

        for payload in payloads:
            yield _trans(self._options, syntax=context.filetype, payload=payload)
