from asyncio import Queue, StreamReader, StreamWriter, create_subprocess_exec
from asyncio.subprocess import DEVNULL, PIPE, Process
from dataclasses import dataclass, field
from json import dumps, loads
from os import linesep
from shutil import which
from typing import (
    Any,
    AsyncIterator,
    Awaitable,
    Callable,
    Dict,
    Iterator,
    Optional,
    Sequence,
    cast,
)

from pynvim import Nvim

from .pkgs.fc_types import Source, SourceCompletion, SourceFeed, SourceSeed
from .pkgs.nvim import call


@dataclass(frozen=True)
class TabNineRequestL2:
    before: str
    after: str
    filename: str
    region_includes_beginning: bool = False
    region_includes_end: bool = False


@dataclass(frozen=True)
class TabNineRequestL1:
    Autocomplete: TabNineRequestL2


@dataclass(frozen=True)
class TabNineRequest:
    request: TabNineRequestL1
    version: str = "2.8.9"


@dataclass(frozen=True)
class TabNineResponseL1:
    new_prefix: str
    old_suffix: str
    new_suffix: str
    kind: Optional[int] = None
    detail: Optional[str] = None
    documentation: Optional[str] = None
    deprecated: Optional[bool] = None


@dataclass(frozen=True)
class TabNineResponse:
    old_prefix: str
    results: Sequence[TabNineResponseL1]
    user_message: Sequence[str] = field(default_factory=tuple)


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


def decode_tabnine_l1(l1: Any) -> Iterator[TabNineResponseL1]:
    if type(l1) is list:
        t9 = cast(Sequence[Dict[str, Any]], l1)
        for el in t9:
            yield TabNineResponseL1(**el)


def decode_tabnine(resp: Any) -> Optional[TabNineResponse]:
    if type(resp) is dict:
        t9 = cast(Dict[str, Any], resp)
        old_prefix = t9["old_prefix"]
        maybe_results = t9["results"]
        results = tuple(decode_tabnine_l1(maybe_results))
        r = TabNineResponse(old_prefix=old_prefix, results=results)
        return r
    else:
        return None


def tabnine_subproc() -> Optional[
    Callable[[TabNineRequest], Awaitable[Optional[TabNineResponse]]]
]:

    tab_nine_exe = "TabNine"
    SEP = linesep.encode()
    proc, stdin, stdout = None, None, None

    async def init() -> None:
        nonlocal proc, stdin, stdout
        if proc and proc.returncode is None:  # type: ignore
            pass
        else:
            proc = await create_subprocess_exec(
                tab_nine_exe, stdin=PIPE, stdout=PIPE, stderr=DEVNULL
            )

    async def request(req: TabNineRequest) -> Any:
        await init()
        p = cast(Process, proc)
        stdin = cast(StreamWriter, p.stdin)
        stdout = cast(StreamReader, p.stdout)

        stdin.write(dumps(req).encode())
        stdin.write(SEP)
        data = await stdout.readuntil(SEP)
        json = data.decode()
        resp = loads(json)
        return decode_tabnine(resp)

    if which(tab_nine_exe):
        return request
    else:
        return None


def encode_tabnine_request() -> TabNineRequest:
    pass


def parse_rows(
    t9: TabNineResponse, feed: SourceFeed, entry_kind_lookup: Dict[int, str],
) -> Iterator[SourceCompletion]:
    position = feed.position
    old_prefix = t9.old_prefix

    for row in t9.results:
        kind = entry_kind_lookup.get(cast(int, row.kind), "Unknown")

        yield SourceCompletion(
            position=position,
            old_prefix=old_prefix,
            new_prefix=row.new_prefix,
            old_suffix=row.old_suffix,
            new_suffix=row.new_suffix,
            kind=kind,
            doc=row.documentation,
        )


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    tabnine_inst = tabnine_subproc()
    entry_kind = await init_lua(nvim)
    entry_kind_lookup = {v: k for k, v in entry_kind.items()}

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        if not tabnine_inst:
            pass
        else:
            resp = await tabnine_inst()
            if resp:
                for row in parse_rows(
                    resp, feed=feed, entry_kind_lookup=entry_kind_lookup
                ):
                    yield row

    return source
