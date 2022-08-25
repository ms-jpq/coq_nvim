from typing import AbstractSet, AsyncIterator

from ...lsp.requests.completion import comp_thirdparty
from ...lsp.types import LSPcomp
from ...shared.types import Context
from ..lsp.worker import Worker as LSPWorker


class Worker(LSPWorker):
    def _request(
        self, context: Context, cached_clients: AbstractSet[str]
    ) -> AsyncIterator[LSPcomp]:
        return comp_thirdparty(
            self._supervisor.nvim,
            short_name=self.options.short_name,
            always_on_top=self.options.always_on_top,
            weight_adjust=self.options.weight_adjust,
            context=context,
            clients=set() if context.manual else cached_clients,
        )
