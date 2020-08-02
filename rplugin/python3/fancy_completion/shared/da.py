from asyncio import create_subprocess_exec
from asyncio.subprocess import PIPE
from dataclasses import dataclass
from importlib.util import module_from_spec, spec_from_file_location
from json import load
from os.path import basename, splitext
from sys import modules
from types import ModuleType
from typing import Any, AsyncIterator, Iterator, Optional, Sequence, TypeVar, cast

T = TypeVar("T")


def or_else(val: Optional[T], default: T) -> T:
    if val is None:
        return default
    else:
        return val


async def anext(aiter: AsyncIterator[T], default: Optional[T] = None) -> Optional[T]:
    try:
        return await aiter.__anext__()
    except StopAsyncIteration:
        return default


def merge(ds1: Any, ds2: Any, replace: bool = False) -> Any:
    if type(ds1) is dict and type(ds2) is dict:
        append = {k: merge(ds1.get(k), v, replace) for k, v in ds2.items()}
        return {**ds1, **append}
    if type(ds1) is list and type(ds2) is list:
        if replace:
            return ds2
        else:
            return [*ds1, *ds2]
    else:
        return ds2


def merge_all(ds1: Any, *dss: Any, replace: bool = False) -> Any:
    res = ds1
    for ds2 in dss:
        res = merge(res, ds2, replace=replace)
    return res


def load_module(path: str) -> ModuleType:
    name, _ = splitext(basename(path))
    spec = spec_from_file_location(name, path, submodule_search_locations=[])
    mod = module_from_spec(spec)
    modules[mod.__name__] = mod
    cast(Any, spec.loader).exec_module(mod)
    return mod


def load_json(path: str) -> Any:
    with open(path, encoding="utf8") as fd:
        return load(fd)


@dataclass(frozen=True)
class ProcReturn:
    code: int
    out: str
    err: str


async def call(prog: str, *args: str) -> ProcReturn:
    proc = await create_subprocess_exec(prog, *args, stdout=PIPE, stderr=PIPE)
    stdout, stderr = await proc.communicate()
    code = cast(int, proc.returncode)
    return ProcReturn(code=code, out=stdout.decode(), err=stderr.decode())


def subsequences(seq: Sequence[T], reverse: bool = False) -> Iterator[Sequence[T]]:
    if not reverse:
        for i in range(1, len(seq)):
            yield seq[:i]
    if reverse:
        for i in range(len(seq) - 1, 0, -1):
            yield seq[i:]
    yield seq
