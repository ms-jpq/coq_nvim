from typing import AsyncIterator

from ...databases.treesitter.database import TDB
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context, Edit


class Worker(BaseWorker[BaseClient, TDB]):
    async def work(self, context: Context) -> AsyncIterator[Completion]:
        match = context.words or context.syms
        words = await self._misc.select(
            self._supervisor.options, word=match, limitless=context.manual
        )

        for word, kind in words:
            edit = Edit(new_text=word)
            cmp = Completion(
                source=self._options.short_name,
                tie_breaker=self._options.tie_breaker,
                label=edit.new_text,
                sort_by=word,
                primary_edit=edit,
                kind=kind,
            )
            yield cmp

