from typing import Iterator, Sequence

from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context, Edit


class Worker(BaseWorker[BaseClient, None]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        cmp = Completion(
            source=self._options.short_name,
            primary_edit=Edit(new_text="TODO"),
        )
        yield (cmp,)

