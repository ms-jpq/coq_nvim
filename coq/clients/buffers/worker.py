from typing import Iterator, Sequence

from ...server.model.database import Database
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context, ContextualEdit


def _comp(src: str, ctx: Context, word: str) -> Completion:
    edit = ContextualEdit(
        old_prefix=ctx.words_before,
        old_suffix=ctx.words_after,
        new_text=word,
        new_prefix=word,
    )
    cmp = Completion(source=src, primary_edit=edit)
    return cmp


class Worker(BaseWorker[BaseClient, Database]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        words = self._misc.suggestions(context.cwd, word=context.words)
        yield tuple(
            _comp(self._options.short_name, ctx=context, word=word) for word in words
        )

