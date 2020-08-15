from asyncio import create_subprocess_exec, get_running_loop
from asyncio.subprocess import PIPE
from dataclasses import dataclass
from functools import partial
from importlib.util import module_from_spec, spec_from_file_location
from json import dump, load
from os import makedirs
from os.path import basename, dirname, exists, splitext
from sys import modules
from types import ModuleType
from typing import (
    Any,
    AsyncIterator,
    Callable,
    Iterator,
    Optional,
    Sequence,
    TypeVar,
    cast,
)

T = TypeVar("T")


def slurp(path: str) -> str:
    with open(path) as fd:
        return fd.read()


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


async def run_in_executor(f: Callable[..., T], *args: Any, **kwargs: Any) -> T:
    loop = get_running_loop()
    cont = partial(f, *args, **kwargs)
    return await loop.run_in_executor(None, cont)


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


def load_json(path: str) -> Optional[Any]:
    if exists(path):
        with open(path, encoding="utf8") as fd:
            return load(fd)
    else:
        return None


def dump_json(path: str, json: Any) -> None:
    parent = dirname(path)
    makedirs(parent, exist_ok=True)
    with open(path, "w") as fd:
        return dump(json, fd, ensure_ascii=False, indent=2)


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
