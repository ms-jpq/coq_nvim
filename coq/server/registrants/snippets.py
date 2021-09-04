from asyncio import sleep, gather
from contextlib import suppress
from json import JSONDecodeError, loads
from os import scandir
from pathlib import Path
from typing import Iterable, Iterator, MutableSequence, Sequence, Tuple

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

_Times = Tuple[Path, float]
_DECODER = new_decoder(LoadedSnips)


async def _pre_load(
    paths: Iterable[Path],
) -> Tuple[Sequence[_Times], Sequence[_Times]]:
    pre_compiled: MutableSequence[_Times] = []
    user_defined: MutableSequence[_Times] = []

    def cont() -> None:
        for p in paths:
            pre = p / "coq+snippets+v2.json"
            user = p / "coq+snippets+v1"

            with suppress(OSError):
                mtime = pre.stat().st_mtime
                pre_compiled.append((pre, mtime))

            with suppress(OSError):
                for p in scandir(user):
                    path = Path(p.path)
                    if path.suffix in {".snip"} and p.is_file():
                        mtime = p.stat().st_mtime
                        user_defined.append((path, mtime))

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
            pass
            # loaded = await _load(paths)
            # if not loaded:
            #     await sleep(0)
            #     await awrite(nvim, LANG("snip parse empty"))
            # for _, l in loaded:
            #     await stack.sdb.populate(l)

    go(nvim, aw=cont())


atomic.exec_lua(f"{compile_snips.name}()", ())
