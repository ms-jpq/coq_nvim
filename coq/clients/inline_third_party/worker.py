from typing import AsyncIterator

from ...lsp.requests.completion import comp_thirdparty_inline
from ...shared.types import Completion, Context
from ..inline.worker import Worker as InlineWorker


class Worker(InlineWorker):
    async def _work(self, context: Context) -> AsyncIterator[Completion]:
        async with self._work_lock:
            async for comp in comp_thirdparty_inline(
                short_name=self._options.short_name,
                always_on_top=self._options.always_on_top,
                weight_adjust=self._options.weight_adjust,
                context=context,
                chunk=self._supervisor.match.max_results * 2,
                clients=set(),
            ):
                for row in comp.items:
                    yield row
