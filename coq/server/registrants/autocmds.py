from asyncio import Handle, get_running_loop
from itertools import repeat
from json import loads
from typing import (
    AbstractSet,
    Iterator,
    Mapping,
    MutableMapping,
    MutableSequence,
    MutableSet,
    Optional,
    Sequence,
    Tuple,
)

from pynvim.api.nvim import Nvim
from pynvim_pp.api import buf_filetype, cur_buf, list_bufs, win_close
from pynvim_pp.float_win import list_floatwins
from pynvim_pp.lib import async_call, go
from std2.pickle import new_decoder

from ...consts import SNIPPET_ARTIFACTS
from ...registry import atomic, autocmd, rpc
from ...snippets.types import ASnips, ParsedSnippet
from ...treesitter.request import async_request
from ...treesitter.types import Payload
from ..rt_types import Stack
from ..state import state


@rpc(blocking=True)
def _kill_float_wins(nvim: Nvim, stack: Stack) -> None:
    wins = tuple(list_floatwins(nvim))
    if len(wins) != 2:
        for win in wins:
            win_close(nvim, win=win)


autocmd("WinEnter") << f"lua {_kill_float_wins.name}()"

_EXTS: Mapping[str, AbstractSet[str]] = {}
_SNIPPETS: Mapping[str, Sequence[ParsedSnippet]] = {}


@rpc(blocking=True)
def _load_snips(nvim: Nvim, stack: Stack) -> None:
    srcs = stack.settings.clients.snippets.sources

    async def cont() -> None:
        global _EXTS, _SNIPPETS

        json = SNIPPET_ARTIFACTS.read_text("UTF8")
        snippets: ASnips = loads(json)

        exts: MutableMapping[str, MutableSet[str]] = {}
        s_acc: MutableMapping[str, MutableSequence[ParsedSnippet]] = {}
        for label, (ets, snips) in snippets.items():
            if not srcs or label in srcs:
                for src, dests in ets.items():
                    acc = exts.setdefault(src, set())
                    for d in dests:
                        acc.add(d)

                for ext, snps in snips.items():
                    ac = s_acc.setdefault(ext, [])
                    ac.extend(snps)

        _EXTS, _SNIPPETS = exts, s_acc
        await stack.sdb.add_exts(exts)

    go(nvim, aw=cont())


atomic.exec_lua(f"{_load_snips.name}()", ())

_DECODER = new_decoder(Sequence[ParsedSnippet])
_SEEN: MutableSet[str] = set()


@rpc(blocking=True)
def _ft_changed(nvim: Nvim, stack: Stack) -> None:
    buf = cur_buf(nvim)
    ft = buf_filetype(nvim, buf=buf)

    async def cont() -> None:
        await stack.bdb.ft_update(buf.number, filetype=ft)
        if ft not in _SEEN:
            _SEEN.add(ft)

            def cont() -> Iterator[Tuple[str, ParsedSnippet]]:
                stack, seen = [ft], {ft}
                while stack:
                    ext = stack.pop()
                    for et in _EXTS.get(ft, ()):
                        if et not in seen:
                            seen.add(et)
                            stack.append(et)

                    snippets = _SNIPPETS.get(ext, ())
                    snips: Sequence[ParsedSnippet] = _DECODER(snippets)
                    yield from zip(repeat(ext), snips)

            snips: MutableMapping[str, MutableSequence[ParsedSnippet]] = {}

            for filetype, snip in cont():
                acc = snips.setdefault(filetype, [])
                acc.append(snip)

            await stack.sdb.populate(snips)

    go(nvim, aw=cont())


autocmd("FileType") << f"lua {_ft_changed.name}()"
atomic.exec_lua(f"{_ft_changed.name}()", ())


@rpc(blocking=True)
def _insert_enter(nvim: Nvim, stack: Stack) -> None:
    heavy_bufs = state().heavy_bufs
    buf = cur_buf(nvim)

    async def cont() -> None:
        if buf.number in heavy_bufs:
            payloads: Sequence[Payload] = ()
        else:
            payloads = [p async for p in async_request(nvim)]
        await stack.tdb.new_nodes(
            {payload["text"]: payload["kind"] for payload in payloads}
        )

    go(nvim, aw=cont())


autocmd("InsertEnter") << f"lua {_insert_enter.name}()"

_HANDLE: Optional[Handle] = None


@rpc(blocking=True)
def _when_idle(nvim: Nvim, stack: Stack) -> None:
    global _HANDLE
    if _HANDLE:
        _HANDLE.cancel()

    def cont() -> None:
        s = state()
        bufs = list_bufs(nvim, listed=False)
        stack.bdb.vacuum({buf.number for buf in bufs} | s.heavy_bufs)
        _insert_enter(nvim, stack=stack)
        stack.supervisor.notify_idle()

    get_running_loop().call_later(
        stack.settings.limits.idle_time,
        lambda: go(nvim, aw=async_call(nvim, cont)),
    )


autocmd("CursorHold", "CursorHoldI") << f"lua {_when_idle.name}()"

