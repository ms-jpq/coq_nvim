from inspect import getmembers, isfunction
from os.path import exists, join
from typing import Any, Callable, Iterator, Mapping, Optional, Sequence, Tuple
from ...shared.da import  load_module

from ...clients import around, buffers, lsp, paths, tmux, tree_sitter
from ...shared.consts import load_hierarchy, module_entry_point


def load_extern(main_name: str) -> Optional[Callable[..., Any]]:
    for path in load_hierarchy:
        candidate = join(path, main_name)
        if exists(candidate):
            mod = load_module(candidate)
            for member_name, func in getmembers(mod, isfunction):
                if member_name == module_entry_point:
                    return func
    return None
