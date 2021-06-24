from concurrent.futures import CancelledError, Future, InvalidStateError
from contextlib import suppress
from pathlib import Path
from threading import Lock
from typing import Any, Iterator, Optional, Sequence, Tuple
from uuid import UUID, uuid4

from pynvim_pp.lib import threadsafe_call
from std2.pickle import decode

from ...shared.parse import lower
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context, Edit, NvimPos
from .types import Msg

_LUA = (Path(__file__).resolve().parent / "request.lua").read_text("UTF-8")


class Worker(BaseWorker[BaseClient, None]):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: None) -> None:
        self._lock = Lock()
        self._cur: Tuple[UUID, Future] = uuid4(), Future()
        supervisor.nvim.api.exec_lua(_LUA, ())
        super().__init__(supervisor, options=options, misc=misc)

    def _req(self, pos: NvimPos) -> Optional[Any]:
        with self._lock:
            _, fut = self._cur
            fut.cancel()
            self._cur = token, fut = uuid4(), Future()

        def cont() -> None:
            args = (str(token), pos)
            self._supervisor.nvim.api.exec_lua("COQts_req(...)", args)

        threadsafe_call(self._supervisor.nvim, cont)

        try:
            ret = fut.result()
        except CancelledError:
            ret = None

        return ret

    def notify(self, token: UUID, msg: Sequence[Any]) -> None:
        with self._lock:
            c_token, fut = self._cur
            if token == c_token:
                reply, *_ = msg
                with suppress(InvalidStateError):
                    fut.set_result(reply)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        match = lower(context.words or context.syms)
        reply = self._req(context.position)
        resp: Msg = decode(Msg, reply)

        def cont() -> Iterator[Completion]:
            for payload in resp:
                if lower(payload.text).startswith(match) and (
                    len(payload.text) > len(match)
                ):
                    edit = Edit(new_text=payload.text)
                    cmp = Completion(
                        source=self._options.short_name,
                        priority=self._options.priority,
                        primary_edit=edit,
                    )
                    yield cmp

        yield tuple(cont())

