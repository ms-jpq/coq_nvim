from asyncio import gather, sleep
from contextlib import suppress
from json import JSONDecodeError, loads
from math import inf
from os import scandir
from pathlib import Path, PurePath
from typing import Iterable, Iterator, Mapping, MutableMapping, Sequence, Tuple

from pynvim.api.nvim import Nvim
from pynvim_pp.api import iter_rtps
from pynvim_pp.lib import awrite, go
from pynvim_pp.logging import log
from std2.asyncio import run_in_executor
from std2.pickle import DecodeError, new_decoder

from ...lang import LANG
from ...registry import atomic, rpc
from ...shared.timeit import timeit
from ...snippets.types import LoadedSnips
from ..rt_types import Stack

_DECODER = new_decoder(LoadedSnips)


async def _pre_load(
    paths: Iterable[Path],
) -> Tuple[Mapping[Path, float], Mapping[Path, float]]:
    pre_compiled: MutableMapping[Path, float] = {}
    user_defined: MutableMapping[Path, float] = {}

    def cont() -> None:
        for p in paths:
            pre = p / "coq+snippets+v2.json"
            user = p / "coq+snippets+v1"

            with suppress(OSError):
                pre_compiled[pre] = pre.stat().st_mtime

            with suppress(OSError):
                for sp in scandir(user):
                    path = Path(sp.path)
                    if path.suffix in {".snip"} and sp.is_file():
                        user_defined[path] = sp.stat().st_mtime

    await run_in_executor(cont)
    return pre_compiled, user_defined


async def _load(paths: Sequence[Path]) -> Sequence[Tuple[float, LoadedSnips]]:
    def cont() -> Iterator[Tuple[float, LoadedSnips]]:
        for path in paths:
            pre_compiled = path / "coq+snippets+v2.json"

            try:
                mtime = pre_compiled.stat().st_mtime
                raw = pre_compiled.read_text("UTF-8")
            except FileNotFoundError:
                pass
            except OSError as e:
                log.warn("%s", f"{e} :: -- {pre_compiled}")
            else:
                try:
                    json = loads(raw)
                    loaded: LoadedSnips = _DECODER(json)
                except (JSONDecodeError, DecodeError) as e:
                    msg = f"failed to parse :: {e} -- {pre_compiled}"
                    log.warn("%s", msg)
                else:
                    yield mtime, loaded

    return await run_in_executor(lambda: tuple(cont()))


@rpc(blocking=True)
def compile_snips(nvim: Nvim, stack: Stack) -> None:
    paths = tuple(iter_rtps(nvim))

    async def cont() -> None:
        with timeit("LOAD SNIPS", force=True):
            (pre_compiled, user_defined), mtimes = await gather(
                _pre_load(paths), stack.sdb.mtimes()
            )
            compiled = {
                path: mtime
                for path, mtime in pre_compiled.items()
                if mtime > mtimes.get(path, -inf)
            }
            user = {
                path: mtime
                for path, mtime in user_defined.items()
                if mtime > mtimes.get(path, -inf)
            }

            stale = mtimes.keys() - (pre_compiled.keys() | user_defined.keys())

            # if not loaded:
            #     await sleep(0)
            #     await awrite(nvim, LANG("snip parse empty"))
            # for _, l in loaded:
            #     await stack.sdb.populate(l)

    go(nvim, aw=cont())


atomic.exec_lua(f"{compile_snips.name}()", ())
