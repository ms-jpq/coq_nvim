from typing import AsyncIterator

from std2.aitertools import to_async

from ...lsp.types import LSPcomp
from ...shared.types import Context
from ..lsp.worker import Worker as LSPWorker


class Worker(LSPWorker):
    def _request(self, context: Context) -> AsyncIterator[LSPcomp]:
        return to_async(())
