from typing import Iterator, Sequence

from ...server.model.buffers.database import BDB
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context, Edit


def _comp(src: str, word: str) -> Completion:
    edit = Edit(new_text=word)
    cmp = Completion(source=src, primary_edit=edit)
    return cmp


class Worker(BaseWorker[BaseClient, BDB]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        words = self._misc.suggestions(context.words)
        yield tuple(_comp(self._options.short_name, word=word) for word in words)

