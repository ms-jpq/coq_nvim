from asyncio import Handle, get_running_loop
from itertools import repeat
from json import loads
from shutil import unpack_archive
from socket import timeout as TimeoutE
from tempfile import NamedTemporaryFile
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
from urllib.error import URLError

from pynvim.api.nvim import Nvim
from pynvim_pp.api import buf_filetype, cur_buf, get_cwd, win_close
from pynvim_pp.float_win import list_floatwins
from pynvim_pp.lib import async_call, go
from std2.asyncio import run_in_executor
from std2.pickle import new_decoder
from std2.urllib import urlopen

from ...consts import (
    SNIP_VARS,
    SNIPPET_ARTIFACTS,
    SNIPPET_GIT_SHA,
    SNIPPET_HASH_ACTUAL,
    SNIPPET_HASH_DESIRED,
)
from ...registry import atomic, autocmd, rpc
from ...snippets.types import ASnips, ParsedSnippet
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
        await stack.ctdb.swap(cwd)

    go(nvim, aw=cont())


autocmd("DirChanged") << f"lua {_new_cwd.name}()"

_EXTS: Mapping[str, AbstractSet[str]] = {}
_SNIPPETS: Mapping[str, Sequence[ParsedSnippet]] = {}


async def _load_snip_raw(retries: int, timeout: float) -> ASnips:
    desired, sha = SNIPPET_HASH_DESIRED.read_text(), SNIPPET_GIT_SHA.read_text()

    def download() -> None:
        uri = f"https://github.com/ms-jpq/std2/archive/{sha}.tar.gz"
        try:
            with urlopen(uri, timeout=timeout) as resp:
                buf = resp.read()
        except (URLError, TimeoutE):
            pass
        else:
            with NamedTemporaryFile() as fd:
                fd.write(buf)
                fd.flush()
                unpack_archive(fd.name, extract_dir=SNIP_VARS, format="targz")

    for _ in range(retries):
        try:
            actual = SNIPPET_HASH_ACTUAL.read_text("UTF8")
        except FileNotFoundError:
            actual = ""

        if actual != desired:
            await run_in_executor(download)

        try:
            json = SNIPPET_ARTIFACTS.read_text("UTF8")
        except FileNotFoundError:
            pass
        else:
            snippets: ASnips = loads(json)
            return snippets
    else:
        return {}


@rpc(blocking=True)
def _load_snips(nvim: Nvim, stack: Stack) -> None:
    srcs = stack.settings.clients.snippets.sources

    async def cont() -> None:
        global _EXTS, _SNIPPETS

        snippets = await _load_snip_raw(
            stack.settings.limits.download_retries,
            timeout=stack.settings.limits.download_timeout,
        )
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
        payloads = (
            () if buf.number in heavy_bufs else [p async for p in async_request(nvim)]
        )
        await stack.tdb.new_nodes({payload.text: payload.kind for payload in payloads})

    go(nvim, aw=cont())


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
        _insert_enter(nvim, stack=stack)
        stack.supervisor.notify_idle()

    get_running_loop().call_later(
        stack.settings.limits.idle_time,
        lambda: go(nvim, aw=async_call(nvim, cont)),
    )


autocmd("CursorHold", "CursorHoldI") << f"lua {_when_idle.name}()"
