from asyncio import Condition, shield
from locale import strxfrm
from pathlib import Path
from typing import Any, AsyncIterator, Optional, Sequence
from uuid import UUID, uuid4

from pynvim_pp.lib import async_call

from ...shared.parse import lower
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context, Edit
from .database import Database
from .types import Msg

_LUA = (Path(__file__).resolve().parent / "request.lua").read_text("UTF-8")


class Worker(BaseWorker[BaseClient, None]):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: None) -> None:
        self._cond = Condition()
        self._token = uuid4()
        self._resp: Any = None
        self._db = Database(pool=supervisor.pool)
        supervisor.nvim.api.exec_lua(_LUA, ())
        super().__init__(supervisor, options=options, misc=misc)

    async def _req(self) -> Optional[Any]:
        self._token = token = uuid4()

        def cont() -> None:
            args = (str(token),)
            self._supervisor.nvim.api.exec_lua("COQts_req(...)", args)

        await async_call(self._supervisor.nvim, cont)
        async with self._cond:
            await self._cond.wait()
        if self._token == token:
            return self._resp
        else:
            return None

    async def notify(self, token: UUID, msg: Sequence[Any]) -> None:
        if token == self._token:
            reply, *_ = msg
            async with self._cond:
                self._resp = reply
                self._cond.notify_all()

    async def _poll(self) -> None:
        while True:
            async with self._supervisor.idling:
                await self._supervisor.idling.wait()
            reply = await self._req()
            resp: Msg = reply or ()
            await shield(
                self._db.new_nodes({node["text"]: node["kind"] for node in resp})
            )

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        match = context.words or context.syms
        words = await self._db.select(
            self._supervisor.options,
            word=match,
        )

        for word, kind, sort_by in words:
            edit = Edit(new_text=word)
            cmp = Completion(
                source=self._options.short_name,
                tie_breaker=self._options.tie_breaker,
                label=edit.new_text,
                sort_by=sort_by,
                primary_edit=edit,
                kind=kind,
            )
            yield cmp

