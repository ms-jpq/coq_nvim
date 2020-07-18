from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from json import load
from os.path import basename, dirname, splitext
from sys import path as sys_path
from types import ModuleType
from typing import Any, Optional, TypeVar, cast

T = TypeVar("T")


def or_else(val: Optional[T], default: T) -> T:
    if val is None:
        return default
    else:
        return val


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
    parent = dirname(path)
    name, _ = splitext(basename(path))
    if parent not in sys_path:
        sys_path.append(parent)
    spec = spec_from_loader(name, loader=SourceFileLoader(name, path))
    mod = module_from_spec(spec)
    cast(Any, spec.loader).exec_module(mod)
    return mod


def load_json(path: str) -> Any:
    with open(path) as fd:
        return load(fd)
