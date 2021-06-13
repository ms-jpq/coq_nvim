from typing import Iterator, Sequence

from ...server.model.database import Database
from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context


class Worker(BaseWorker[Database]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        yield ()

