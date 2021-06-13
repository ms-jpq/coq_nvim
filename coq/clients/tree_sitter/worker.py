from typing import Iterator, Sequence

from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context


class Worker(BaseWorker[None]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        yield ()

