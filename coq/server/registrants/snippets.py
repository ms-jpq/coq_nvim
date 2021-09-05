from asyncio import gather, sleep
from asyncio.tasks import as_completed
from contextlib import suppress
from itertools import chain
from json import JSONDecodeError, loads
from math import inf
from pathlib import Path
from posixpath import normcase
from string import Template
from textwrap import dedent
from typing import Iterator, Mapping, Tuple

from pynvim.api.nvim import Nvim
from pynvim_pp.api import iter_rtps
from pynvim_pp.lib import async_call, awrite, go
from pynvim_pp.logging import log
from std2.asyncio import run_in_executor
from std2.pickle import DecodeError, new_decoder

from ...lang import LANG
from ...registry import atomic, rpc
from ...shared.timeit import timeit
from ...snippets.types import SCHEMA, LoadedSnips
from ..rt_types import Stack

_DECODER = new_decoder(LoadedSnips)


async def _load_bundled(nvim: Nvim) -> Mapping[Path, float]:
    paths = await async_call(nvim, lambda: tuple(iter_rtps(nvim)))

    def cont() -> Iterator[Tuple[Path, float]]:
        for path in paths:
            json = path / f"coq+snippets+{SCHEMA}.json"
            with suppress(OSError):
                mtime = json.stat().st_mtime
                yield json, mtime

    return {p: m for p, m in await run_in_executor(lambda: tuple(cont()))}


async def _load_user_compiled(vars_dir: Path) -> Mapping[Path, float]:
    def cont() -> Mapping[Path, float]:
        path = vars_dir / "clients" / "snippets" / f"users+{SCHEMA}.json"
        try:
            mtime = path.stat().st_mtime
            return {path: mtime}
        except OSError:
            return {}

    return await run_in_executor(cont)


async def _load_compiled(path: Path, mtime: float) -> Tuple[Path, float, LoadedSnips]:
    def cont() -> LoadedSnips:
        raw = path.read_text("UTF-8")
        json = loads(raw)
        loaded: LoadedSnips = _DECODER(json)
        return loaded

    return path, mtime, await run_in_executor(cont)


@rpc(blocking=True)
def compile_snips(nvim: Nvim, stack: Stack) -> None:
    async def cont() -> None:
        with timeit("LOAD SNIPS", force=True):
            bundled, user_compiled, mtimes = await gather(
                _load_bundled(nvim),
                _load_user_compiled(stack.supervisor.vars_dir),
                stack.sdb.mtimes(),
            )

            stale = mtimes.keys() - (bundled.keys() | user_compiled.keys())
            await stack.sdb.clean(stale)

            if not (bundled or user_compiled):
                await sleep(0)
                await awrite(nvim, LANG("fs snip load empty"))
            else:
                compiled = {
                    path: mtime
                    for path, mtime in chain(bundled.items(), user_compiled.items())
                    if mtime > mtimes.get(path, -inf)
                }

                for fut in as_completed(
                    tuple(
                        _load_compiled(path, mtime) for path, mtime in compiled.items()
                    )
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
                        await awrite(
                            nvim, LANG("fs snip load succ", path=normcase(path))
                        )

    go(nvim, aw=cont())


atomic.exec_lua(f"{compile_snips.name}()", ())
