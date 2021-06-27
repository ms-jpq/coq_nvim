from dataclasses import asdict
from json import dumps, loads
from subprocess import PIPE, Popen
from threading import Event
from typing import IO, Any, Iterator, Optional, Sequence, cast

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
    resp: Response = decode(Response, reply, strict=False)

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


def _proc() -> Popen:
    return Popen((str(T9_BIN),), text=True, stdin=PIPE, stdout=PIPE)


class Worker(BaseWorker[TabnineClient, None]):
    def __init__(
        self, supervisor: Supervisor, options: TabnineClient, misc: None
    ) -> None:
        self._ev = Event()
        self._proc: Optional[Popen] = None
        supervisor.pool.submit(self._install)
        super().__init__(supervisor, options=options, misc=misc)

    def _install(self) -> None:
        ensure_installed(60)
        self._ev.set()

    def _req(self, context: Context) -> Sequence[Completion]:
        if not self._ev.is_set():
            return ()
        else:
            if not self._proc:
                self._proc = _proc()

            req = _encode(context)
            json = dumps(req, check_circular=False, ensure_ascii=False)
            try:
                cast(IO, self._proc.stdin).write(json)
                cast(IO, self._proc.stdin).write("\n")
                cast(IO, self._proc.stdin).flush()
                json = cast(IO, self._proc.stdout).readline()
            except BrokenPipeError:
                self._proc = _proc()
                return ()
            else:
                reply = loads(json)
                cmps = tuple(_decode(self._options, reply=reply))
                return cmps

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        cmps = self._req(context)
        yield cmps

