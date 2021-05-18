# async def init_lua(nvim: Nvim) -> Tuple[Mapping[int, str], Mapping[int, str]]:
# def cont() -> Tuple[Mapping[str, int], Mapping[str, int]]:
# nvim.api.exec_lua("Coq_lsp = require 'Coq/lsp'", ())
# entry_kind = nvim.api.exec_lua("return Coq_lsp.list_entry_kind()", ())
# insert_kind = nvim.api.exec_lua("return Coq_lsp.list_insert_kind()", ())
# return entry_kind, insert_kind

# entry_kind, insert_kind = await call(nvim, cont)
# elookup = defaultdict(lambda: "Unknown", ((v, k) for k, v in entry_kind.items()))
# ilookup = defaultdict(lambda: "PlainText", ((v, k) for k, v in insert_kind.items()))
# return elookup, ilookup


from queue import SimpleQueue
from typing import Any, Tuple, cast, Iterator
from uuid import UUID

from pynvim import Nvim
from std2.pickle import decode

from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context, Edit, NvimPos
from .types import CompletionList, Resp


def _req(nvim: Nvim, token: UUID, pos: NvimPos) -> Resp:
    nvim.api.exec_lua("")

def _parse(resp: Resp) -> Iterator[Completion]:
    pass

class Worker(BaseWorker[SimpleQueue]):
    def __init__(self, supervisor: Supervisor, misc: SimpleQueue) -> None:
        super().__init__(supervisor, misc=misc)

        supervisor.pool.submit(self._poll)

    def _poll(self) -> None:
        while True:
            uuid, msg = cast(Tuple[str, Any], self._misc.get())
            token = UUID(uuid)
            resp = cast(Resp, decode(Resp, msg, strict=False))
            completions = tuple(_parse(resp))
            self._supervisor.report(token, completions=completions)
            if isinstance(resp, CompletionList) and resp.isIncomplete:
                _req(self._supervisor.nvim, token=token, pos=context.position)

    def work(self, token: UUID, context: Context) -> None:
        _req(self._supervisor.nvim, token=token, pos=context.position)
