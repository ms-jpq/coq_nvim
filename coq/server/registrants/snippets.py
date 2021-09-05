from asyncio import gather, sleep
from asyncio.tasks import as_completed
from contextlib import suppress
from datetime import datetime
from itertools import chain
from json import JSONDecodeError, dumps, loads
from math import inf
from pathlib import Path, PurePath
from posixpath import normcase
from string import Template
from tempfile import NamedTemporaryFile
from textwrap import dedent
from typing import Any, Iterable, Iterator, Mapping, Optional, Tuple

from pynvim.api.nvim import Nvim
from pynvim_pp.api import iter_rtps
from pynvim_pp.lib import async_call, awrite, go
from pynvim_pp.logging import log
from std2.asyncio import run_in_executor
from std2.graphlib import recur_sort
from std2.pathlib import walk
from std2.pickle import DecodeError, new_decoder, new_encoder

from ...lang import LANG
from ...registry import atomic, rpc
from ...shared.timeit import timeit
from ...snippets.types import SCHEMA, LoadedSnips
from ..rt_types import Stack

BUNDLED_PATH_TPL = Template("coq+snippets+${schema}.json")
_USER_PATH_TPL = Template("users+${schema}.json")
_SUB_PATH = PurePath("clients", "snippets")


def user_snip_paths(rtp: Iterable[Path], user_path: Optional[Path]) -> Iterator[Path]:
    if user_path:
        yield user_path
    for path in rtp:
        yield path / "coq+user+snippets"


async def _load_bundled(
    nvim: Nvim, user_path: Optional[Path]
) -> Tuple[Mapping[Path, float], Mapping[Path, float]]:
    rtp = await async_call(nvim, lambda: tuple(iter_rtps(nvim)))

    def c1() -> Iterator[Tuple[Path, float]]:
        for path in rtp:
            json = path / BUNDLED_PATH_TPL.substitute(schema=SCHEMA)
            with suppress(OSError):
                mtime = json.stat().st_mtime
                yield json, mtime

    def c2() -> Iterator[Tuple[Path, float]]:
        for path in user_snip_paths(rtp, user_path=user_path):
            with suppress(OSError):
                for p in walk(path):
                    mtime = p.stat().st_mtime
                    yield p, mtime

    m1 = {p: m for p, m in await run_in_executor(lambda: tuple(c1()))}
    m2 = {p: m for p, m in await run_in_executor(lambda: tuple(c2()))}
    return m1, m2


def _paths(vars_dir: Path) -> Tuple[Path, Path]:
    compiled = vars_dir / _SUB_PATH / _USER_PATH_TPL.substitute(schema=SCHEMA)
    meta = vars_dir / _SUB_PATH / "meta.json"
    return compiled, meta


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
                m2 = new_encoder(Mapping[Path, float])(json)
            except (JSONDecodeError, DecodeError):
                meta.unlink()

        return m1, m2

    return await run_in_executor(cont)


async def _load_compiled(path: Path, mtime: float) -> Tuple[Path, float, LoadedSnips]:
    decoder = new_decoder(LoadedSnips)

    def cont() -> LoadedSnips:
        raw = path.read_text("UTF-8")
        json = loads(raw)
        loaded: LoadedSnips = decoder(json)
        return loaded

    return path, mtime, await run_in_executor(cont)


def jsonify(o: Any) -> str:
    json = dumps(recur_sort(o), check_circular=False, ensure_ascii=False, indent=2)
    return json


async def dump_compiled(
    vars_dir: Path, mtimes: Mapping[Path, float], snip: LoadedSnips
) -> None:
    m_json = jsonify(new_encoder(Mapping[Path, float])(mtimes))
    s_json = jsonify(new_encoder(LoadedSnips)(snip))

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


@rpc(blocking=True)
def compile_snips(nvim: Nvim, stack: Stack) -> None:
    async def cont() -> None:
        with timeit("LOAD SNIPS", force=True):
            (
                (bundled, user_snips_mtimes),
                (user_compiled, user_compiled_mtimes),
                mtimes,
            ) = await gather(
                _load_bundled(nvim, user_path=None),
                _load_user_compiled(stack.supervisor.vars_dir),
                stack.sdb.mtimes(),
            )

            stale = mtimes.keys() - (bundled.keys() | user_compiled.keys())
            compiled = {
                path: mtime
                for path, mtime in chain(bundled.items(), user_compiled.items())
                if mtime > mtimes.get(path, -inf)
            }
            updated_user_snips = {
                normcase(path): datetime.fromtimestamp(mtime)
                for path, mtime in user_snips_mtimes.items()
                if mtime > user_compiled_mtimes.get(path, -inf)
            }

            await stack.sdb.clean(stale)
            if not (bundled or user_compiled):
                await sleep(0)
                await awrite(nvim, LANG("fs snip load empty"))

            for fut in as_completed(
                tuple(_load_compiled(path, mtime) for path, mtime in compiled.items())
            ):
                try:
                    path, mtime, loaded = await fut
                except (OSError, JSONDecodeError, DecodeError) as e:
                    tpl = """
                    Failed to load compiled snips
                    ${e}
                    """
                    log.warn("%s", Template(dedent(tpl)).substitute(e=type(e)))
                else:
                    await stack.sdb.populate(path, mtime=mtime, loaded=loaded)
                    await awrite(nvim, LANG("fs snip load succ", path=normcase(path)))

            if updated_user_snips:
                await awrite(nvim, LANG("fs snip needs compile"))

    go(nvim, aw=cont())


atomic.exec_lua(f"{compile_snips.name}()", ())
