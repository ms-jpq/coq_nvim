from dataclasses import replace

from pynvim.api.nvim import Nvim

from ...registry import rpc
from ...shared.repeat import sanitize
from ...shared.types import ContextualEdit, Edit
from ..context import context
from ..edit import edit
from ..runtime import Stack
from ..state import state


def _edit(prev: Edit) -> Edit:
    sanitized = sanitize(prev)
    new_edit = (
        ContextualEdit(
            new_text=sanitized.new_text, old_prefix="", new_prefix=sanitized.new_text
        )
        if type(sanitized) is Edit
        else sanitized
    )
    return new_edit


@rpc(blocking=True)
def repeat(nvim: Nvim, stack: Stack) -> None:
    ctx = context(
        nvim, db=stack.bdb, options=stack.settings.match, state=state(), manual=True
    )
    s = state(context=ctx)
    metric = s.last_edit
    sanitized = _edit(metric.comp.primary_edit)
    new_metric = replace(
        metric, comp=replace(metric.comp, primary_edit=sanitized, secondary_edits=())
    )
    edit(nvim, stack=stack, state=s, metric=new_metric, synthetic=True)
