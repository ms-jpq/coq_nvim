from typing import Any, Sequence
from uuid import UUID

from pynvim import Nvim

from ...registry import rpc
from ..runtime import Stack


@rpc(blocking=True)
def comm(nvim: Nvim, stack: Stack, args: Sequence[Any]) -> None:
    uid, *msg = args
    uuid = UUID(uid)
    stack.supervisor.notify(uuid, msg)

