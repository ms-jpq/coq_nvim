from typing import Iterator, Sequence

from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context

_SOURCE = "TS"


class Worker(BaseWorker[None]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        yield ()

