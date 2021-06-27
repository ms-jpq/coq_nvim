from concurrent.futures.thread import ThreadPoolExecutor
from dataclasses import asdict
from json import dumps, loads
from subprocess import PIPE, Popen
from threading import Lock
from typing import Any, Callable, Iterator, Optional, Sequence

from pynvim_pp.logging import log
from std2.pickle import decode

from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import TabnineClient
from ...shared.types import Completion, Context, ContextualEdit
from .install import T9_BIN, ensure_installed
from .types import ReqL1, ReqL2, Request, Response

_VERSION = "3.2.28"


def _encode(context: Context) -> Any:
    l2 = ReqL2(
        filename=context.filename,
        before=context.line_before,
        after=context.line_after,
        max_num_results=10,
    )
    l1 = ReqL1(Autocomplete=l2)
    req = Request(request=l1, version=_VERSION)
    return asdict(req)


def _decode(client: TabnineClient, reply: Any) -> Iterator[Completion]:
    resp: Response = decode(Response, reply)

    for result in resp.results:
        edit = ContextualEdit(
            old_prefix=resp.old_prefix,
            new_prefix=result.new_prefix,
            old_suffix=result.old_suffix,
            new_text=result.new_prefix + result.new_suffix,
        )
        label = (result.new_prefix.splitlines() or ("",))[-1] + (
            result.new_suffix.splitlines() or ("",)
        )[0]
        cmp = Completion(
            primary_edit=edit,
            source=client.short_name,
            tie_breaker=client.tie_breaker,
            label=label,
        )
        yield cmp


class Worker(BaseWorker[TabnineClient, None]):
    def __init__(
        self, supervisor: Supervisor, options: TabnineClient, misc: None
    ) -> None:
        super().__init__(supervisor, options=options, misc=misc)

    def _req(self, context: Context) -> Sequence[Completion]:
        if not self._proc:
            self._proc = Popen((str(T9_BIN),), text=True, stdin=PIPE, stdout=PIPE)

        req = _encode(context)
        json = dumps(req, check_circular=False, ensure_ascii=False)
        self._proc.stdin.writelines((json,))
        self._proc.stdin.flush()
        json = self._proc.stdout.readline()
        reply = loads(json)
        cmps = tuple(_decode(self._options, reply=reply))
        return cmps

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        cmps = self._req(context)
        yield cmps

