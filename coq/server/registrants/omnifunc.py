from typing import Any, Literal, Mapping, Sequence, Tuple, Union, cast

from pynvim import Nvim

from ...registry import rpc, settings
from ...shared.types import Completion

from ...shared.nvim.completions import
from ..context import context
from ..runtime import Stack


@rpc(blocking=True)
def omnifunc(
    nvim: Nvim, stack: Stack, args: Tuple[Tuple[Literal[0, 1], str]]
) -> Union[int, Sequence[Mapping[str, Any]]]:
    (op, _), *_ = args

    if op == 1:
        return -1
    else:
        ctx = context(
            nvim,
            unifying_chars=stack.settings.match.unifying_chars,
            buf=None,
            filename=None,
            filetype=None,
        )
        fut = stack.supervisor.collect(ctx)
        completions = cast(Sequence[Completion], fut.result())
        return ({"word": "--TODO--"},)


settings["completefunc"] = omnifunc.name
