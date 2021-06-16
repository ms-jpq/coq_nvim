from typing import Iterator, Sequence

from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context, Edit

_SOURCE = "TS"


class Worker(BaseWorker[None]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        cmp = Completion(
            source=_SOURCE,
            primary_edit=Edit(new_text="TODO"),
        )
        yield (cmp,)

