from uuid import uuid4

from pynvim.api.nvim import Nvim

from ...registry import rpc
from ...shared.types import Edit
from ..edit import edit
from ..nvim.completions import UserData
from ..runtime import Stack
from ..state import state


def _edit(prev: Edit) -> Edit:
    return prev


@rpc(blocking=True)
def repeat(nvim: Nvim, stack: Stack) -> None:
    s = state()
    data = UserData(
        uid=uuid4(),
        instance=uuid4(),
        sort_by="",
        change_uid=uuid4(),
        primary_edit=_edit(s.last_edit),
        secondary_edits=(),
        doc=None,
        extern=None,
    )
    edit(nvim, stack=stack, state=s, data=data, synthetic=True)
