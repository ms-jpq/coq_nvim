from typing import Iterator, Sequence

from ...server.model.buffers.database import BDB
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import WordbankClient
from ...shared.types import Completion, Context, Edit


def _comp(client: WordbankClient, word: str) -> Completion:
    edit = Edit(new_text=word)
    cmp = Completion(
        source=client.short_name, priority=client.priority, primary_edit=edit
    )
    return cmp


class Worker(BaseWorker[WordbankClient, BDB]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        match = context.words or (context.syms if self._options.match_syms else "")
        words = self._misc.suggestions(match)
        yield tuple(_comp(self._options, word=word) for word in words)

