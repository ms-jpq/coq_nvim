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


from concurrent.futures import ThreadPoolExecutor
from queue import SimpleQueue
from typing import Any, Iterator, Mapping, cast, Sequence, Tuple
from uuid import UUID

from pynvim import Nvim

from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context, Edit
from .types import Resp


def _req(nvim: Nvim) -> Resp:
    nvim.api.exec_lua("")


def _ask(nvim: Nvim) -> Iterator[Resp]:
    pass


class Worker(BaseWorker[SimpleQueue]):
    def __init__(self, supervisor: Supervisor, misc: SimpleQueue) -> None:
        super().__init__(supervisor, misc=misc)

        supervisor.pool.submit(self._poll)

    def _poll(self) -> None:
        while True:
            token, msg = cast(Tuple[str, Any], self._misc.get())


    def work(self, token: UUID, context: Context) -> Tuple[UUID,Sequence[Completion]]:
        def cont() -> Iterator[Completion]:
            for pane, words in self._panes.items():
                if not (pane.window_active and pane.pane_active):
                    for word in words:
                        edit = Edit(new_text=word)
                        completion = Completion(
                            position=context.position, primary_edit=edit
                        )
                        yield completion

        return token, tuple(cont())
