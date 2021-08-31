from asyncio import create_subprocess_exec, shield, sleep
from asyncio.locks import Lock
from asyncio.subprocess import Process
from contextlib import suppress
from itertools import chain
from json import dumps, loads
from json.decoder import JSONDecodeError
from os import X_OK, access, linesep
from pathlib import PurePath
from subprocess import DEVNULL, PIPE
from typing import AbstractSet, Any, AsyncIterator, Iterator, Optional

from pynvim_pp.lib import awrite, go
from pynvim_pp.logging import log
from std2.pickle import DecodeError, new_decoder, new_encoder

from ...lang import LANG
from ...shared.parse import is_word
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient, Options
from ...shared.types import Completion, Context, ContextualEdit
from .install import ensure_updated, t9_bin
from .types import ReqL1, ReqL2, Request, Response

_VERSION = "3.2.28"

_DECODER = new_decoder(Response, strict=False)
_ENCODER = new_encoder(Request)


def _encode(options: Options, context: Context, limit: int) -> Any:
    row, _ = context.position
    before = linesep.join(chain(context.lines_before, (context.line_before,)))
    after = linesep.join(chain((context.line_after,), context.lines_after))
    ibg = row - options.proximate_lines <= 0
    ieof = row + options.proximate_lines >= context.line_count

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


def _sort_by(unifying_chars: AbstractSet[str], new_text: str) -> str:
    def cont() -> Iterator[str]:
        seen_syms = False
        for char in reversed(new_text):
            if is_word(char, unifying_chars=unifying_chars):
                if seen_syms:
                    break
                else:
                    yield char
            else:
                yield char
                seen_syms = True

    sort_by = "".join(reversed(tuple(cont())))
    return sort_by


def _decode(
    unifying_chars: AbstractSet[str], client: BaseClient, reply: Any
) -> Iterator[Completion]:
    try:
        resp: Response = _DECODER(reply)
    except DecodeError as e:
        log.warn("%s", e)
    else:
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
                weight_adjust=client.weight_adjust,
                label=label,
                sort_by=_sort_by(unifying_chars, new_text=edit.old_prefix),
                primary_edit=edit,
                icon_match=None,
            )
            yield cmp


async def _proc(bin: PurePath, cwd: PurePath) -> Optional[Process]:
    try:
        proc = await create_subprocess_exec(
            bin,
            stdin=PIPE,
            stdout=PIPE,
            stderr=DEVNULL,
            cwd=cwd,
        )
    except FileNotFoundError:
        return None
    else:
        return proc


class Worker(BaseWorker[BaseClient, None]):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: None) -> None:
        self._lock = Lock()
        self._bin: Optional[PurePath] = None
        self._proc: Optional[Process] = None
        self._cwd: Optional[PurePath] = None
        super().__init__(supervisor, options=options, misc=misc)
        go(supervisor.nvim, aw=self._install())
        go(supervisor.nvim, aw=self._poll())

    async def _poll(self) -> None:
        try:
            while True:
                await sleep(9)
        finally:
            proc = self._proc
            if proc:
                with suppress(ProcessLookupError):
                    proc.kill()
                await proc.wait()

    async def _install(self) -> None:
        vars_dir = self._supervisor.vars_dir / "clients" / "t9"
        installed = access(t9_bin(vars_dir), X_OK)

        if not installed:
            for _ in range(9):
                await sleep(0)
            await awrite(self._supervisor.nvim, LANG("begin T9 download"))

        self._bin = await ensure_updated(
            vars_dir,
            retries=self._supervisor.limits.download_retries,
            timeout=self._supervisor.limits.download_timeout,
        )

        if not self._bin:
            await awrite(self._supervisor.nvim, LANG("failed T9 download"))
        elif self._bin and not installed:
            await awrite(self._supervisor.nvim, LANG("end T9 download"))

    async def _clean(self) -> None:
        proc = self._proc
        if proc:
            self._proc = None
            with suppress(ProcessLookupError):
                proc.kill()
            await proc.wait()

    async def _comm(self, cwd: PurePath, json: str) -> Optional[str]:
        async def cont() -> Optional[str]:
            async with self._lock:
                if self._bin and not self._proc:
                    self._proc = await _proc(self._bin, cwd=cwd)
                    if self._proc:
                        self._cwd = cwd
                if not self._proc:
                    return None
                else:
                    assert self._proc.stdin and self._proc.stdout
                    try:
                        self._proc.stdin.write(json.encode())
                        self._proc.stdin.write(b"\n")
                        await self._proc.stdin.drain()
                        out = await self._proc.stdout.readline()
                    except ConnectionError:
                        return await self._clean()
                    else:
                        return out.decode()

        if self._lock.locked():
            return None
        else:
            return await shield(cont())

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        if self._cwd != context.cwd:
            await self._clean()

        if self._bin:
            req = _encode(
                self._supervisor.options,
                context=context,
                limit=self._supervisor.options.max_results,
            )
            json = dumps(req, check_circular=False, ensure_ascii=False)
            reply = await self._comm(context.cwd, json=json)
            if reply:
                try:
                    resp = loads(reply)
                except JSONDecodeError as e:
                    log.warn("%s", e)
                else:
                    for comp in _decode(
                        self._supervisor.options.unifying_chars,
                        client=self._options,
                        reply=resp,
                    ):
                        yield comp
