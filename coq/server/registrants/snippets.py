from asyncio import gather, sleep
from asyncio.tasks import as_completed
from contextlib import suppress
from dataclasses import dataclass
from datetime import datetime
from itertools import chain
from json import JSONDecodeError, dumps, loads
from math import inf
from os import linesep
from pathlib import Path, PurePath
from posixpath import expandvars, normcase
from string import Template
from tempfile import NamedTemporaryFile
from textwrap import dedent
from typing import (
    AbstractSet,
    Any,
    Iterable,
    Iterator,
    Mapping,
    Optional,
    Sequence,
    Tuple,
)

from pynvim.api.nvim import Nvim
from pynvim_pp.api import iter_rtps
from pynvim_pp.lib import async_call, awrite, go
from pynvim_pp.logging import log
from std2.asyncio import run_in_executor
from std2.graphlib import recur_sort
from std2.pathlib import walk
from std2.pickle import DecodeError, new_decoder, new_encoder

from ...lang import LANG
from ...paths.show import fmt_path
from ...registry import atomic, rpc
from ...shared.context import EMPTY_CONTEXT
from ...shared.timeit import timeit
from ...shared.types import Edit, Mark, SnippetEdit
from ...snippets.loaders.load import load_direct
from ...snippets.loaders.neosnippet import load_neosnippet
from ...snippets.parse import parse
from ...snippets.types import SCHEMA, LoadedSnips, ParsedSnippet
from ..rt_types import Stack
from ..state import state

BUNDLED_PATH_TPL = Template("coq+snippets+${schema}.json")
_USER_PATH_TPL = Template("users+${schema}.json")
_SUB_PATH = PurePath("clients", "snippets")


@dataclass(frozen=True)
class Compiled:
    path: PurePath
    filetype: str
    exts: AbstractSet[str]
    parsed: Sequence[Tuple[ParsedSnippet, Edit, Sequence[Mark]]]


async def _bundled_mtimes(
    nvim: Nvim,
) -> Mapping[Path, float]:
    rtp = await async_call(nvim, lambda: tuple(iter_rtps(nvim)))

    def c1() -> Iterator[Tuple[Path, float]]:
        for path in rtp:
            json = path / BUNDLED_PATH_TPL.substitute(schema=SCHEMA)
            with suppress(OSError):
                mtime = json.stat().st_mtime
                yield json, mtime

    return {p: m for p, m in await run_in_executor(lambda: tuple(c1()))}


async def _snippet_paths(nvim: Nvim, user_path: Optional[Path]) -> Sequence[Path]:
    def cont() -> Iterator[Path]:
        if user_path:
            usp = Path(expandvars(user_path))
            resolved = (
                usp if usp.is_absolute() else Path(nvim.funcs.stdpath("config")) / usp
            )
            yield Path(normcase(resolved))
        for path in iter_rtps(nvim):
            yield path / "coq-user-snippets"

    return await async_call(nvim, lambda: tuple(cont()))


async def user_mtimes(
    nvim: Nvim, user_path: Optional[Path]
) -> Tuple[Sequence[Path], Mapping[Path, float]]:
    paths = await _snippet_paths(nvim, user_path=user_path)

    def cont() -> Iterator[Tuple[Path, float]]:
        for path in paths:
            with suppress(OSError):
                for p in walk(path):
                    if p.suffix in {".snip"}:
                        mtime = p.stat().st_mtime
                        yield p, mtime

    return paths, {p: m for p, m in await run_in_executor(cont)}


def _paths(vars_dir: Path) -> Tuple[Path, Path]:
    compiled = vars_dir / _SUB_PATH / _USER_PATH_TPL.substitute(schema=SCHEMA)
    meta = vars_dir / _SUB_PATH / "meta.json"
    return compiled, meta


async def _load_compiled(path: Path, mtime: float) -> Tuple[Path, float, LoadedSnips]:
    decoder = new_decoder(LoadedSnips)

    def cont() -> LoadedSnips:
        raw = path.read_text("UTF-8")
        json = loads(raw)
        loaded: LoadedSnips = decoder(json)
        return loaded

    return path, mtime, await run_in_executor(cont)


async def _load_user_compiled(
    vars_dir: Path,
) -> Tuple[Mapping[Path, float], Mapping[Path, float]]:
    compiled, meta = _paths(vars_dir)

    def cont() -> Tuple[Mapping[Path, float], Mapping[Path, float]]:
        m1: Mapping[Path, float] = {}
        m2: Mapping[Path, float] = {}
        with suppress(OSError):
            mtime = compiled.stat().st_mtime
            m1 = {compiled: mtime}

        with suppress(OSError):
            raw = meta.read_text("UTF-8")
            try:
                json = loads(raw)
                m2 = new_decoder(Mapping[Path, float])(json)
            except (JSONDecodeError, DecodeError):
                meta.unlink()

        return m1, m2

    return await run_in_executor(cont)


def jsonify(o: Any) -> str:
    json = dumps(recur_sort(o), check_circular=False, ensure_ascii=False, indent=2)
    return json


async def _dump_compiled(
    vars_dir: Path, mtimes: Mapping[Path, float], loaded: LoadedSnips
) -> None:
    m_json = jsonify(new_encoder(Mapping[Path, float])(mtimes))
    s_json = jsonify(new_encoder(LoadedSnips)(loaded))

    paths = _paths(vars_dir)
    compiled, meta = paths
    for p in paths:
        p.parent.mkdir(parents=True, exist_ok=True)

    with suppress(FileNotFoundError), NamedTemporaryFile(dir=compiled.parent) as fd:
        fd.write(s_json.encode("UTF-8"))
        fd.flush()
        Path(fd.name).replace(compiled)

    with suppress(FileNotFoundError), NamedTemporaryFile(dir=meta.parent) as fd:
        fd.write(m_json.encode("UTF-8"))
        fd.flush()
        Path(fd.name).replace(meta)


def _trans(
    unifying_chars: AbstractSet[str], snips: Iterable[ParsedSnippet]
) -> Iterator[Tuple[ParsedSnippet, Edit, Sequence[Mark]]]:
    for snip in snips:
        edit = SnippetEdit(grammar=snip.grammar, new_text=snip.content)
        parsed, marks = parse(
            unifying_chars,
            context=EMPTY_CONTEXT,
            snippet=edit,
            visual="",
        )
        yield snip, parsed, marks


def compile_one(
    stack: Stack, path: PurePath, lines: Iterable[Tuple[int, str]]
) -> Compiled:
    filetype, exts, snips = load_neosnippet(path, lines=lines)
    parsed = tuple(_trans(stack.settings.match.unifying_chars, snips=snips))

    compiled = Compiled(
        path=path,
        filetype=filetype,
        exts=exts,
        parsed=parsed,
    )
    return compiled


async def compile_user_snippets(nvim: Nvim, stack: Stack) -> None:
    _, mtimes = await user_mtimes(nvim, user_path=None)
    loaded = await run_in_executor(
        lambda: load_direct(lsp=(), neosnippet=mtimes, ultisnip=())
    )
    _ = tuple(
        _trans(stack.settings.match.unifying_chars, snips=loaded.snippets.values())
    )
    await _dump_compiled(stack.supervisor.vars_dir, mtimes=mtimes, loaded=loaded)


@rpc(blocking=True)
def _load_snips(nvim: Nvim, stack: Stack) -> None:
    async def cont() -> None:
        with timeit("LOAD SNIPS"):
            (
                bundled,
                (user_compiled, user_compiled_mtimes),
                (_, user_snips_mtimes),
                mtimes,
            ) = await gather(
                _bundled_mtimes(nvim),
                _load_user_compiled(stack.supervisor.vars_dir),
                user_mtimes(nvim, user_path=stack.settings.clients.snippets.user_path),
                stack.sdb.mtimes(),
            )

            stale = mtimes.keys() - (bundled.keys() | user_compiled.keys())
            compiled = {
                path: mtime
                for path, mtime in chain(bundled.items(), user_compiled.items())
                if mtime > mtimes.get(path, -inf)
            }
            updated_user_snips = {
                path: datetime.fromtimestamp(mtime)
                for path, mtime in user_snips_mtimes.items()
                if mtime > user_compiled_mtimes.get(path, -inf)
            }

            await stack.sdb.clean(stale)
            if not (bundled or user_compiled):
                await sleep(0)
                await awrite(nvim, LANG("fs snip load empty"))

            s = state()
            for fut in as_completed(
                tuple(_load_compiled(path, mtime) for path, mtime in compiled.items())
            ):
                try:
                    path, mtime, loaded = await fut
                except (OSError, JSONDecodeError, DecodeError) as e:
                    tpl = """
                    Failed to load compiled snips
                    ${e}
                    """.rstrip()
                    log.warn("%s", Template(dedent(tpl)).substitute(e=type(e)))
                else:
                    await stack.sdb.populate(path, mtime=mtime, loaded=loaded)
                    await awrite(
                        nvim,
                        LANG(
                            "fs snip load succ",
                            path=fmt_path(s.cwd, path=path, is_dir=False),
                        ),
                    )

            if updated_user_snips:
                paths = linesep.join(
                    f"{fmt_path(s.cwd, path=p, is_dir=False)} -- {m.strftime(stack.settings.display.time_fmt)}"
                    for p, m in updated_user_snips.items()
                )
                await awrite(nvim, LANG("fs snip needs compile", paths=paths))

    go(nvim, aw=cont())


atomic.exec_lua(f"{_load_snips.name}()", ())
