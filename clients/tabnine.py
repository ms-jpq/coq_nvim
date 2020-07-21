from asyncio import (
    Queue,
    StreamReader,
    StreamWriter,
    Task,
    create_subprocess_exec,
    create_task,
    sleep,
)
from asyncio.subprocess import DEVNULL, PIPE, Process
from dataclasses import asdict, dataclass, field
from itertools import chain
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
from pynvim.api.buffer import Buffer

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
    task: Task = create_task(sleep(0))

    async def init() -> None:
        nonlocal proc, stdin, stdout
        if proc and proc.returncode is None:  # type: ignore
            pass
        else:
            proc = await create_subprocess_exec(
                tab_nine_exe, stdin=PIPE, stdout=PIPE, stderr=DEVNULL
            )

    async def request(req: TabNineRequest) -> Any:
        nonlocal task
        await init()
        p = cast(Process, proc)
        stdin = cast(StreamWriter, p.stdin)
        stdout = cast(StreamReader, p.stdout)

        stdin.write(dumps(asdict(req)).encode())
        stdin.write(SEP)
        task.cancel()
        task = create_task(stdout.readuntil(SEP))
        data = await task
        json = data.decode()
        resp = loads(json)
        return decode_tabnine(resp)

    if which(tab_nine_exe):
        return request
    else:
        return None


async def buf_lines(nvim: Nvim) -> Sequence[str]:
    def cont() -> Sequence[str]:
        buf: Buffer = nvim.api.get_current_buf()
        lines = nvim.api.buf_get_lines(buf, 0, -1, True)
        return lines

    return await call(nvim, cont)


async def encode_tabnine_request(nvim: Nvim, feed: SourceFeed) -> TabNineRequest:
    row = feed.position.row
    context = feed.context
    lines = await buf_lines(nvim)
    lines_before = lines[:row]
    lines_after = lines[row:]
    before = "".join(chain(lines_before, (context.line_before,)))
    after = "".join(chain((context.line_after,), lines_after))

    l2 = TabNineRequestL2(before=before, after=after, filename=feed.filename)
    l1 = TabNineRequestL1(Autocomplete=l2)
    req = TabNineRequest(request=l1)
    return req


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
            req = await encode_tabnine_request(nvim, feed=feed)
            resp = await tabnine_inst(req)
            if resp:
                for row in parse_rows(
                    resp, feed=feed, entry_kind_lookup=entry_kind_lookup
                ):
                    yield row

    return source
