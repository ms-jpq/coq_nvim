from uuid import UUID

from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Context


class Worker(BaseWorker[None]):
    def __init__(self, supervisor: Supervisor, misc: None) -> None:
        super().__init__(supervisor, misc=misc)

    def work(self, token: UUID, context: Context) -> None:
        self._supervisor.report(token, completions=tuple())
