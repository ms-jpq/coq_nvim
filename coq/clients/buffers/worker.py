from typing import Iterator, Sequence

from ...server.databases.buffers.database import BDB
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import WordbankClient
from ...shared.types import Completion, Context, Edit


class Worker(BaseWorker[WordbankClient, BDB]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        match = context.words or (context.syms if self._options.match_syms else "")
        words = self._misc.words(
            self._supervisor.options,
            filetype=context.filetype,
            word=match,
        )

        def cont() -> Iterator[Completion]:
            for word, sort_by in words:
                edit = Edit(new_text=word)
                cmp = Completion(
                    source=self._options.short_name,
                    tie_breaker=self._options.tie_breaker,
                    label=edit.new_text,
                    sort_by=sort_by,
                    primary_edit=edit,
                )
                yield cmp

        yield tuple(cont())

