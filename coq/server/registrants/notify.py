from typing import Any
from uuid import UUID

from pynvim import Nvim

from ...registry import rpc
from ..runtime import Stack


@rpc(blocking=True)
def notify(nvim: Nvim, stack: Stack, uid: str, *msg: Any) -> None:
    uuid = UUID(uid)
    stack.supervisor.notify(uuid, msg)

