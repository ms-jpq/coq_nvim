from typing import AsyncIterator

from ...lsp.requests.completion import comp_thirdparty_inline
from ...lsp.types import LSPcomp
from ...shared.types import Context
from ..inline.worker import Worker as InlineWorker


class Worker(InlineWorker):
    def _request(self, context: Context) -> AsyncIterator[LSPcomp]:
        return comp_thirdparty_inline(
            short_name=self._options.short_name,
            always_on_top=self._options.always_on_top,
            weight_adjust=self._options.weight_adjust,
            context=context,
            chunk=self._supervisor.match.max_results * 2,
            clients=set(),
        )
