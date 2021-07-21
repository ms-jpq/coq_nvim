from asyncio import Handle, get_running_loop
from typing import Iterator, MutableMapping, MutableSet, Optional, Sequence

from pynvim.api.nvim import Nvim
from pynvim_pp.api import buf_filetype, cur_buf, list_bufs, win_close
from pynvim_pp.float_win import list_floatwins
from pynvim_pp.lib import async_call, go
from std2.pickle import new_decoder

from ...registry import atomic, autocmd, rpc
from ...snippets.artifacts import SNIPPETS
from ...snippets.types import ParsedSnippet
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


def _in_soc(stack: Stack, label: str) -> bool:
    srcs = stack.settings.clients.snippets.sources
    return not srcs or label in srcs


@rpc(blocking=True)
def _load_snips(nvim: Nvim, stack: Stack) -> None:
    async def cont() -> None:
        exts: MutableMapping[str, MutableSet[str]] = {}
        for label, (ets, _) in SNIPPETS.items():
            if _in_soc(stack, label=label):
                for src, dests in ets.items():
                    acc = exts.setdefault(src, set())
                    for d in dests:
                        acc.add(d)

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

            def cont() -> Iterator[ParsedSnippet]:
                for label, (_, snippets) in SNIPPETS.items():
                    if _in_soc(stack, label=label):
                        snips = snippets.get(ft, ())
                        s: Sequence[ParsedSnippet] = _DECODER(snips)
                        yield from s

            await stack.sdb.populate({ft: cont()})

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

