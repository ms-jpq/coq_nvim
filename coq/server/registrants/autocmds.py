from asyncio import Handle, get_running_loop, sleep
from asyncio.locks import Lock
from asyncio.tasks import gather
from itertools import repeat
from json import loads
from json.decoder import JSONDecodeError
from pathlib import Path, PurePath
from socket import AF_SNA
from typing import (
    AbstractSet,
    Iterable,
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
from pynvim_pp.api import buf_filetype, buf_get_option, cur_buf, get_cwd, win_close
from pynvim_pp.float_win import list_floatwins
from pynvim_pp.lib import async_call, awrite, go
from pynvim_pp.logging import log
from std2.asyncio import run_in_executor
from std2.pickle import new_decoder

from ...databases.snippets.database import SDB
from ...lang import LANG
from ...registry import atomic, autocmd, rpc
from ...snippets.types import ASnips, ParsedSnippet
from ...snippets.loaders.load import load as load_snips_from_paths
from ...tmux.parse import snapshot
from ...treesitter.request import async_request
from ..rt_types import Stack
from ..state import state


@rpc(blocking=True)
def _kill_float_wins(nvim: Nvim, stack: Stack) -> None:
    wins = tuple(list_floatwins(nvim))
    if len(wins) != 2:
        for win in wins:
            win_close(nvim, win=win)


autocmd("WinEnter") << f"lua {_kill_float_wins.name}()"


@rpc(blocking=True)
def _new_cwd(nvim: Nvim, stack: Stack) -> None:
    cwd = get_cwd(nvim)

    async def cont() -> None:
        s = state(cwd=PurePath(cwd))
        await stack.ctdb.swap(s.cwd)

    go(nvim, aw=cont())


autocmd("DirChanged") << f"lua {_new_cwd.name}()"


_DECODER = new_decoder(ASnips)


async def _load_snip_raw(paths: Iterable[Path]) -> ASnips:
    def cont() -> ASnips:
        for path in paths:
            candidate = path / "coq+snippets.json"
            try:
                json = candidate.read_text("UTF8")
            except (FileNotFoundError, PermissionError):
                pass
            else:
                try:
                    snips = _DECODER(loads(json))

                except JSONDecodeError as e:
                    log.warn("%s", e)
                else:
                    return snips
        else:
            return {}

    return await run_in_executor(cont)


_LOCK: Optional[Lock] = None
_EXTS: Mapping[str, AbstractSet[str]] = {}
_SNIPPETS: Mapping[str, Sequence[ParsedSnippet]] = {}
_SEEN_SNIP_TYPES: MutableSet[str] = set()


def _load_compiled_snips(nvim: Nvim, stack: Stack) -> None:
    srcs = stack.settings.clients.snippets.compiled_sources
    paths = tuple(map(Path, nvim.list_runtime_paths()))

    async def cont() -> None:
        global _LOCK, _EXTS, _SNIPPETS
        assert not _LOCK
        _LOCK = Lock()

        async with _LOCK:
            snippets = await _load_snip_raw(paths)
            if not snippets:
                for _ in range(9):
                    await sleep(0)
                await awrite(nvim, LANG("no snippets found"))

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

    if stack.settings.clients.snippets.enabled:
        go(nvim, aw=cont())




def _load_user_defined_snips(nvim: Nvim, stack: Stack) -> None:
    ultisnips_paths = []
    neosnippet_paths = []
    for path_str in nvim.list_runtime_paths():
        path = Path(path_str)
        if (neosnippet_path := path / "neosnippets").exists():
            neosnippet_paths.append(neosnippet_path)
        if (ultisnips_path := path / "UltiSnips").exists():
            ultisnips_paths.append(ultisnips_path)
        if (ultisnips_path := path / "snippets").exists():
            ultisnips_paths.append(ultisnips_path)

    async def cont() -> None:
        global _LOCK, _EXTS, _SNIPPETS
        assert not _LOCK
        _LOCK = Lock()

        async with _LOCK:
            snippets = await run_in_executor(
                lambda: load_snips_from_paths(
                    lsp={},
                    neosnippet={str(path): path for path in neosnippet_paths},
                    ultisnip={str(path): path for path in ultisnips_paths},
                )
            )

            exts: MutableMapping[str, MutableSet[str]] = {}
            s_acc: MutableMapping[str, MutableSequence[ParsedSnippet]] = {}
            for ets, snips in snippets.values():
                for src, dests in ets.items():
                    acc = exts.setdefault(src, set())
                    for d in dests:
                        acc.add(d)

                for ext, snps in snips.items():
                    ac = s_acc.setdefault(ext, [])
                    ac.extend(snps)

            _EXTS, _SNIPPETS = exts, s_acc
            await stack.sdb.add_exts(exts)

    if stack.settings.clients.snippets.enabled:
        go(nvim, aw=cont())


@rpc(blocking=True)
def _load_snips(nvim: Nvim, stack: Stack) -> None:
    if stack.settings.clients.snippets.load_from == 'compiled_sources':
        _load_compiled_snips(nvim, stack)
    else:
        _load_user_defined_snips(nvim, stack)


atomic.exec_lua(f"{_load_snips.name}()", ())


async def _add_snips(ft: str, db: SDB) -> None:
    while not _LOCK:
        await sleep(0)

    async with _LOCK:
        if ft not in _SEEN_SNIP_TYPES:
            _SEEN_SNIP_TYPES.add(ft)

            def cont() -> Iterator[Tuple[str, ParsedSnippet]]:
                stack, seen = [ft], {ft}
                while stack:
                    ext = stack.pop()
                    for et in _EXTS.get(ft, ()):
                        if et not in seen:
                            seen.add(et)
                            stack.append(et)

                    snippets = _SNIPPETS.get(ext, ())
                    yield from zip(repeat(ext), snippets)

            snips: MutableMapping[str, MutableSequence[ParsedSnippet]] = {}

            for filetype, snip in cont():
                acc = snips.setdefault(filetype, [])
                acc.append(snip)

            await db.populate(snips)


@rpc(blocking=True)
def _ft_changed(nvim: Nvim, stack: Stack) -> None:
    buf = cur_buf(nvim)
    ft = buf_filetype(nvim, buf=buf)

    async def cont() -> None:
        await stack.bdb.ft_update(buf.number, filetype=ft)
        if stack.settings.clients.snippets.enabled:
            await _add_snips(ft, db=stack.sdb)

    go(nvim, aw=cont())


autocmd("FileType") << f"lua {_ft_changed.name}()"
atomic.exec_lua(f"{_ft_changed.name}()", ())


@rpc(blocking=True)
def _insert_enter(nvim: Nvim, stack: Stack) -> None:
    nono_bufs = state().nono_bufs
    buf = cur_buf(nvim)

    async def c1() -> None:
        await stack.bdb.del_bufs(nono_bufs)

    async def c2() -> None:
        payloads = (
            () if buf.number in nono_bufs else [p async for p in async_request(nvim)]
        )
        await stack.tdb.new_nodes(payloads)

    go(nvim, aw=gather(c1(), c2()))


autocmd("InsertEnter") << f"lua {_insert_enter.name}()"


@rpc(blocking=True)
def _on_focus(nvim: Nvim, stack: Stack) -> None:
    async def cont() -> None:
        snap = await snapshot(stack.settings.match.unifying_chars)
        await stack.tmdb.periodical(snap)

    go(nvim, aw=cont())


autocmd("FocusGained") << f"lua {_on_focus.name}()"

_HANDLE: Optional[Handle] = None


@rpc(blocking=True)
def _when_idle(nvim: Nvim, stack: Stack) -> None:
    global _HANDLE
    if _HANDLE:
        _HANDLE.cancel()

    def cont() -> None:
        buf = cur_buf(nvim)
        buf_type: str = buf_get_option(nvim, buf=buf, key="buftype")
        if buf_type == "terminal":
            nvim.api.buf_detach(buf)
            state(nono_bufs={buf.number})

        _insert_enter(nvim, stack=stack)
        stack.supervisor.notify_idle()

    get_running_loop().call_later(
        stack.settings.limits.idle_timeout,
        lambda: go(nvim, aw=async_call(nvim, cont)),
    )


autocmd("CursorHold", "CursorHoldI") << f"lua {_when_idle.name}()"
