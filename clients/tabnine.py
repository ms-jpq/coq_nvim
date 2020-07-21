from asyncio import Queue, StreamReader, StreamWriter, create_subprocess_exec
from asyncio.subprocess import DEVNULL, PIPE, Process
from json import dumps, loads
from os import linesep
from shutil import which
from typing import Any, AsyncIterator, Awaitable, Callable, Dict, cast

from pynvim import Nvim

from .pkgs.fc_types import Source, SourceCompletion, SourceFeed, SourceSeed
from .pkgs.nvim import call

tab_nine_exe = "tabnine"
tab_nine_ver = ""


async def init_lua(nvim: Nvim) -> Dict[str, int]:
    def cont() -> Dict[str, int]:
        nvim.api.exec_lua(
            "fuzzy_completion_tabnine = require 'fuzzy_completion_lsp'", ()
        )
        entry_kind = nvim.api.exec_lua(
            "return fuzzy_completion_tabnine.list_entry_kind()", ()
        )
        return entry_kind

    return await call(nvim, cont)


async def tabnine_subproc() -> Callable[[Any], Awaitable[Any]]:
    proc, stdin, stdout = None, None, None

    async def init() -> None:
        nonlocal proc, stdin, stdout
        if proc and proc.returncode is None:  # type: ignore
            pass
        else:
            proc = await create_subprocess_exec(
                tab_nine_exe, stdin=PIPE, stdout=PIPE, stderr=DEVNULL
            )

    async def request(req: Any) -> Any:
        await init()
        p = cast(Process, proc)
        stdin = cast(StreamWriter, p.stdin)
        stdout = cast(StreamReader, p.stdout)

        stdin.write(dumps(req))
        stdin.write(linesep)
        data = await stdout.readuntil(linesep)
        json = data.decode()
        return loads(json)

    return request


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    tabnine_inst = which(tab_nine_exe) is not None
    entry_kind = await init_lua(nvim)
    entry_kind_lookup = {v: k for k, v in entry_kind.items()}

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        if not tabnine_inst:
            return
        else:
            position = feed.position
            yield SourceCompletion(
                position=position,
                old_prefix="",
                new_prefix="",
                old_suffix="",
                new_suffix="",
            )

    return source
