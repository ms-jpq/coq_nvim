from asyncio import create_subprocess_exec, shield
from asyncio.locks import Lock
from asyncio.subprocess import Process
from contextlib import suppress
from itertools import chain
from json import dumps, loads
from os import X_OK, access, linesep
from subprocess import DEVNULL, PIPE
from typing import Any, AsyncIterator, Iterator, Optional

from pynvim_pp.lib import awrite, go
from pynvim_pp.logging import log
from std2.pickle import new_decoder, new_encoder

from ...lang import LANG
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient, Options
from ...shared.types import Completion, Context, ContextualEdit
from .install import T9_BIN, ensure_updated
from .types import ReqL1, ReqL2, Request, Response

_VERSION = "3.2.28"

_DECODER = new_decoder(Response, strict=False)
_ENCODER = new_encoder(Request)


def _encode(options: Options, context: Context, limit: int) -> Any:
    row, _ = context.position
    before = linesep.join(chain(context.lines_before, (context.line_before,)))
    after = linesep.join(chain((context.line_after,), context.lines_after))
    ibg = row - options.context_lines <= 0
    ieof = row + options.context_lines >= context.line_count

    l2 = ReqL2(
        filename=context.filename,
        before=before,
        after=after,
        region_includes_beginning=ibg,
        region_includes_end=ieof,
        max_num_results=None if context.manual else limit,
    )
    l1 = ReqL1(Autocomplete=l2)
    req = Request(request=l1, version=_VERSION)
    return _ENCODER(req)


def _decode(client: BaseClient, reply: Any) -> Iterator[Completion]:
    resp: Response = _DECODER(reply)

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
            source=client.short_name,
            tie_breaker=client.tie_breaker,
            label=label,
            sort_by=edit.new_text,
            primary_edit=edit,
        )
        yield cmp


async def _proc() -> Process:
    proc = await create_subprocess_exec(
        T9_BIN,
        stdin=PIPE,
        stdout=PIPE,
        stderr=DEVNULL,
    )
    return proc


class Worker(BaseWorker[BaseClient, None]):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: None) -> None:
        self._lock, self._installed = Lock(), False
        self._proc: Optional[Process] = None
        super().__init__(supervisor, options=options, misc=misc)
        go(supervisor.nvim, aw=self._install())

    async def _install(self) -> None:
        self._installed = installed = access(T9_BIN, X_OK)

        if not self._installed:
            await awrite(self._supervisor.nvim, LANG("begin T9 download"))

        self._installed = await ensure_updated(
            self._supervisor.limits.download_retries,
            timeout=self._supervisor.limits.download_timeout,
        )

        if not self._installed:
            await awrite(self._supervisor.nvim, LANG("failed T9 download"))
        elif self._installed and not installed:
            await awrite(self._supervisor.nvim, LANG("end T9 download"))

    async def _comm(self, json: str) -> str:
        async def cont() -> str:
            async with self._lock:
                if not self._proc:
                    self._proc = await _proc()
                    try:
                        assert self._proc.stdin
                        self._proc.stdin.write(json.encode())
                        self._proc.stdin.write(b"\n")
                        await self._proc.stdin.drain()
                        assert self._proc.stdout
                        out = await self._proc.stdout.readline()
                    except (BrokenPipeError, ConnectionResetError):
                        with suppress(ProcessLookupError):
                            self._proc.kill()
                        await self._proc.wait()
                        return "{}"
                    else:
                        return out.decode()
                else:
                    return "{}"

        if self._lock.locked():
            log.warn("%s", "T9 locked")
            return ""
        else:
            return await shield(cont())

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        if self._installed:
            req = _encode(
                self._supervisor.options,
                context=context,
                limit=self._supervisor.options.max_results,
            )
            json = dumps(req, check_circular=False, ensure_ascii=False)
            json = await self._comm(json)
            reply = loads(json)
            for comp in _decode(self._options, reply=reply):
                yield comp
