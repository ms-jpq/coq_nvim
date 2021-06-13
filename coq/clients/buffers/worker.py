from typing import Iterator, Sequence

from ...server.model.database import Database
from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context, ContextualEdit

_PREFIX_LEN = 3


def _comp(ctx: Context, word: str) -> Completion:
    edit = ContextualEdit(
        old_prefix=ctx.words_before,
        old_suffix=ctx.words_after,
        new_text=word,
        new_prefix=word,
    )
    cmp = Completion(primary_edit=edit)
    return cmp


class Worker(BaseWorker[Database]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        words = self._misc.suggestions(context.words, prefix_len=_PREFIX_LEN)
        yield tuple(_comp(context, word=word) for word in words)

