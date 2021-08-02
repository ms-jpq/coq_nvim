from asyncio import Handle, get_running_loop
from contextlib import suppress
from itertools import repeat
from json import loads
from json.decoder import JSONDecodeError
from pathlib import Path
from shutil import rmtree, unpack_archive
from socket import timeout as TimeoutE
from tempfile import NamedTemporaryFile, TemporaryDirectory
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
from pynvim_pp.lib import async_call, awrite, go
from pynvim_pp.logging import log
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


async def _load_snip_raw(nvim: Nvim, retries: int, timeout: float) -> ASnips:
    desired, sha = SNIPPET_HASH_DESIRED.read_text(), SNIPPET_GIT_SHA.read_text()

    def download() -> None:
        uri = f"https://github.com/ms-jpq/coq.artifacts/archive/{sha}.tar.gz"
        try:
            with urlopen(uri, timeout=timeout) as resp:
                buf = resp.read()
        except (URLError, TimeoutE) as e:
            log.warn("%s", e)
        else:
            with NamedTemporaryFile() as fd:
                fd.write(buf)
                fd.flush()
            with TemporaryDirectory() as tmp:
                unpack_archive(fd.name, extract_dir=tmp, format="targz")
                Path(tmp).replace(SNIP_VARS)

    def load() -> ASnips:
        try:
            json = SNIPPET_ARTIFACTS.read_text("UTF8")
        except FileNotFoundError:
            return {}
        else:
            try:
                snippets: ASnips = loads(json)
            except JSONDecodeError as e:
                log.warn("%s", e)
                with suppress(FileNotFoundError):
                    rmtree(SNIP_VARS)
                return {}
            else:
                return snippets

    async def cont() -> ASnips:
        for _ in range(retries):
            try:
                actual = SNIPPET_HASH_ACTUAL.read_text("UTF8")
            except FileNotFoundError:
                actual = ""

            if actual != desired:
                await run_in_executor(download)
            else:
                snippets = load()
                if snippets:
                    return snippets
        else:
            return {}

    snips = load()
    if not snips:
        return await cont()
    else:
        go(nvim, aw=cont())
        return snips


_EXTS: Mapping[str, AbstractSet[str]] = {}
_SNIPPETS: Mapping[str, Sequence[ParsedSnippet]] = {}
_SEEN_SNIP_TYPES: MutableSet[str] = set()


@rpc(blocking=True)
def _load_snips(nvim: Nvim, stack: Stack) -> None:
    srcs = stack.settings.clients.snippets.sources

    async def cont() -> None:
        global _EXTS, _SNIPPETS

        snippets = await _load_snip_raw(
            stack.settings.limits.download_retries,
            timeout=stack.settings.limits.download_timeout,
        )
        _SEEN_SNIP_TYPES.clear()
        if not snippets:
            await awrite(nvim, "nooooo", error=True)

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


@rpc(blocking=True)
def _ft_changed(nvim: Nvim, stack: Stack) -> None:
    buf = cur_buf(nvim)
    ft = buf_filetype(nvim, buf=buf)

    async def cont() -> None:
        await stack.bdb.ft_update(buf.number, filetype=ft)
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
