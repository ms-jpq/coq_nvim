from asyncio import Condition
from locale import strxfrm
from pathlib import Path
from typing import Any, AsyncIterator, Optional, Sequence
from uuid import UUID, uuid4

from pynvim_pp.lib import async_call

from ...shared.parse import lower
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context, Edit, NvimPos
from .types import Msg

_LUA = (Path(__file__).resolve().parent / "request.lua").read_text("UTF-8")


class Worker(BaseWorker[BaseClient, None]):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: None) -> None:
        self._cond = Condition()
        self._token = uuid4()
        self._resp: Any = None
        supervisor.nvim.api.exec_lua(_LUA, ())
        super().__init__(supervisor, options=options, misc=misc)

    async def _req(self, pos: NvimPos) -> Optional[Any]:
        self._token = token = uuid4()

        def cont() -> None:
            args = (str(token), pos)
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

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        match = lower(context.words or context.syms)
        prefix = match[: self._supervisor.options.exact_matches]
        reply = await self._req(context.position)
        resp: Msg = reply or ()
        for payload in resp:
            ltext = lower(payload["text"])
            if ltext.startswith(prefix) and (len(payload["text"]) > len(match)):
                edit = Edit(new_text=payload["text"])
                cmp = Completion(
                    source=self._options.short_name,
                    tie_breaker=self._options.tie_breaker,
                    label=edit.new_text.strip(),
                    sort_by=strxfrm(ltext),
                    primary_edit=edit,
                    kind=payload["kind"],
                )
                yield cmp

