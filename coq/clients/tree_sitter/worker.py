from typing import AsyncIterator

from ...databases.treesitter.database import Database
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context, Edit


class Worker(BaseWorker[BaseClient, Database]):
    async def work(self, context: Context) -> AsyncIterator[Completion]:
        match = context.words or context.syms
        words = await self._misc.select(
            self._supervisor.options,
            word=match,
            limit=self._options.limit,
        )

        for word, kind, sort_by in words:
            edit = Edit(new_text=word)
            cmp = Completion(
                source=self._options.short_name,
                tie_breaker=self._options.tie_breaker,
                label=edit.new_text,
                sort_by=sort_by,
                primary_edit=edit,
                kind=kind,
            )
            yield cmp

