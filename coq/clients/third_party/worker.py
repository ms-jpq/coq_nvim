from typing import AsyncIterator

from ...lsp.requests.completion import request_thirdparty
from ...lsp.types import LSPcomp
from ...shared.types import Context
from ..lsp.worker import Worker as LSPWorker


class Worker(LSPWorker):
    def _request(self, context: Context) -> AsyncIterator[LSPcomp]:
        return request_thirdparty(
            self._supervisor.nvim,
            short_name=self._options.short_name,
            weight_adjust=self._options.weight_adjust,
            context=context,
        )
