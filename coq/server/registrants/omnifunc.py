from dataclasses import asdict
from typing import Any, Literal, Mapping, Sequence, Tuple, Union, cast

from pynvim import Nvim

from ...registry import rpc, settings
from ...shared.types import Completion
from ..context import context
from ..runtime import Stack
from ..trans import trans


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
        comp = trans(stack, context=ctx, completions=completions)
        serialized = tuple(
            {k: v for k, v in asdict(cmp).items() if v is not None} for cmp in comp
        )
        return serialized


settings["completefunc"] = omnifunc.name
