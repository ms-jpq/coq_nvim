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


def _reactor(
    pool: ThreadPoolExecutor,
) -> Callable[[TabnineClient, Context], Sequence[Completion]]:
    proc: Optional[Popen] = None
    lock = Lock()

    def cont() -> None:
        nonlocal proc
        try:
            ensure_installed()
            while True:
                if proc:
                    proc.wait()
                else:
                    proc = Popen((str(T9_BIN),), text=True, stdin=PIPE, stdout=PIPE)
        except Exception as e:
            log.exception("%s", e)

    def req(client: TabnineClient, context: Context) -> Sequence[Completion]:
        if not proc or not proc.stdin or not proc.stdout:
            return ()
        else:
            req = _encode(context)
            json = dumps(req, check_circular=False, ensure_ascii=False)
            proc.stdin.writelines((json,))
            proc.stdin.flush()
            json = proc.stdout.readline()
            reply = loads(json)
            cmps = tuple(_decode(client, reply=reply))
            return cmps

    pool.submit(cont)
    return req


class Worker(BaseWorker[TabnineClient, None]):
    def __init__(
        self, supervisor: Supervisor, options: TabnineClient, misc: None
    ) -> None:
        self._req = _reactor(supervisor.pool)
        super().__init__(supervisor, options=options, misc=misc)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        cmps = self._req(self._options, context)
        yield cmps

