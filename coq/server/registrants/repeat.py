from uuid import uuid4

from pynvim.api.nvim import Nvim

from ...registry import rpc
from ...shared.repeat import sanitize
from ...shared.types import ContextualEdit, Edit
from ..context import context
from ..edit import edit
from ..nvim.completions import UserData
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
    sanitized = _edit(s.last_edit)
    data = UserData(
        uid=uuid4(),
        instance=uuid4(),
        sort_by="",
        change_uid=uuid4(),
        primary_edit=sanitized,
        secondary_edits=(),
        doc=None,
        extern=None,
    )
    edit(nvim, stack=stack, state=s, data=data, synthetic=True)
