from asyncio import (
    LimitOverrunError,
    create_subprocess_exec,
    create_task,
    shield,
    sleep,
)
from asyncio.locks import Lock
from asyncio.subprocess import Process
from contextlib import suppress
from itertools import chain, count
from json import dumps, loads
from json.decoder import JSONDecodeError
from os import X_OK, access
from pathlib import PurePath
from subprocess import DEVNULL, PIPE
from typing import Any, AsyncIterator, Iterator, Mapping, Optional, Sequence

from pynvim_pp.lib import decode, encode
from pynvim_pp.logging import log, suppress_and_log
from pynvim_pp.nvim import Nvim
from std2.pickle.decoder import new_decoder
from std2.pickle.encoder import new_encoder
from std2.pickle.types import DecodeError
from std2.platform import OS, os

from ...lang import LANG
from ...lsp.protocol import PROTOCOL
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import T9Client
from ...shared.types import Completion, Context, ContextualEdit, Doc
from .install import ensure_updated, t9_bin
from .types import ReqL1, ReqL2, Request, RespL1, Response

_VERSION = "4.4.204"

_DECODER = new_decoder[RespL1](RespL1, strict=False)
_ENCODER = new_encoder[Request](Request)


def _encode(context: Context, id: int, limit: int) -> Any:
    row, _ = context.position
    before = context.linefeed.join(chain(context.lines_before, (context.line_before,)))
    after = context.linefeed.join(chain((context.line_after,), context.lines_after))
    ibg = row - context.win_size <= 0
    ieof = row + context.win_size >= context.line_count

    l2 = ReqL2(
        correlation_id=id,
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


def _decode(
    client: T9Client, ellipsis: str, syntax: str, id: int, reply: Response
) -> Iterator[Completion]:
    if (
        not isinstance(reply, Mapping)
        or ((r_id := reply.get("correlation_id")) and r_id != id)
        or not isinstance((old_prefix := reply.get("old_prefix")), str)
        or not isinstance((results := reply.get("results")), Sequence)
    ):
        log.warn("%s", reply)
    else:
        for result in results:
            try:
                resp = _DECODER(result)
            except DecodeError as e:
                log.warn("%s", e)
            else:
                new_text = resp.new_prefix + resp.new_suffix
                edit = ContextualEdit(
                    old_prefix=old_prefix,
                    new_prefix=resp.new_prefix,
                    old_suffix=resp.old_suffix,
                    new_text=new_text,
                )

                pre_lines = resp.new_prefix.splitlines() or ("",)
                post_lines = resp.new_suffix.splitlines() or ("",)
                label_pre, *pre = pre_lines
                label_post, *post = post_lines
                e_pre = ellipsis if pre else ""
                e_post = ellipsis if post else ""
                label = label_pre + e_pre + label_post + e_post
                *_, s_pre = pre_lines
                s_post, *_ = post_lines
                sort_by = s_pre + s_post

                doc = Doc(text=new_text, syntax=syntax) if e_pre or e_post else None

                kind = PROTOCOL.CompletionItemKind.get(resp.kind)
                cmp = Completion(
                    source=client.short_name,
                    always_on_top=client.always_on_top,
                    weight_adjust=client.weight_adjust,
                    label=label,
                    sort_by=sort_by,
                    primary_edit=edit,
                    adjust_indent=False,
                    kind=kind or "",
                    icon_match=kind,
                    doc=doc,
                )
                yield cmp


def _nice() -> None:
    with suppress(ImportError, PermissionError):
        from os import nice

        nice(19)


async def _proc(bin: PurePath, cwd: PurePath) -> Optional[Process]:
    kwargs = {} if os is OS.windows else {"preexec_fn": _nice}
    try:
        proc = await create_subprocess_exec(
            bin,
            "--client=coq.nvim",
            stdin=PIPE,
            stdout=PIPE,
            stderr=DEVNULL,
            cwd=cwd,
            **kwargs,
        )
    except FileNotFoundError:
        return None
    else:
        return proc


class Worker(BaseWorker[T9Client, None]):
    def __init__(self, supervisor: Supervisor, options: T9Client, misc: None) -> None:
        self._lock = Lock()
        self._bin: Optional[PurePath] = None
        self._proc: Optional[Process] = None
        self._cwd: Optional[PurePath] = None
        self._count = count()
        super().__init__(supervisor, options=options, misc=misc)
        create_task(self._install())
        create_task(self._poll())

    async def _poll(self) -> None:
        with suppress_and_log():
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
        with suppress_and_log():
            vars_dir = self._supervisor.vars_dir / "clients" / "t9"
            bin_path = t9_bin(vars_dir)
            if access(bin_path, X_OK):
                self._bin = bin_path
            else:
                for _ in range(9):
                    await sleep(0)
                await Nvim.write(LANG("begin T9 download"))

                self._bin = await ensure_updated(
                    vars_dir,
                    retries=self._supervisor.limits.download_retries,
                    timeout=self._supervisor.limits.download_timeout,
                )

                if not self._bin:
                    await Nvim.write(LANG("failed T9 download"))
                else:
                    await Nvim.write(LANG("end T9 download"))

    async def _clean(self) -> None:
        if proc := self._proc:
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
                        self._proc.stdin.write(encode(json))
                        self._proc.stdin.write(b"\n")
                        await self._proc.stdin.drain()
                        out = await self._proc.stdout.readline()
                    except (ConnectionError, LimitOverrunError, ValueError):
                        await self._clean()
                        return None
                    else:
                        return decode(out)

        if self._lock.locked():
            return None
        else:
            return await shield(cont())

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        async with self._work_lock:
            if self._cwd != context.cwd:
                await self._clean()

            if self._bin:
                id = next(self._count)
                req = _encode(
                    context,
                    id=id,
                    limit=self._supervisor.match.max_results,
                )
                json = dumps(req, check_circular=False, ensure_ascii=False)
                if reply := await self._comm(context.cwd, json=json):
                    try:
                        resp = loads(reply)
                    except JSONDecodeError as e:
                        log.warn("%s", e)
                    else:
                        for comp in _decode(
                            self._options,
                            ellipsis=self._supervisor.display.pum.ellipsis,
                            syntax=context.filetype,
                            id=id,
                            reply=resp,
                        ):
                            yield comp
