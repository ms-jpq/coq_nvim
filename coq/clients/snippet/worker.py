from typing import Iterator, Sequence

from ...server.model.snippets.database import SDB
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import SnippetClient
from ...shared.types import Completion, Context, SnippetEdit


class Worker(BaseWorker[SnippetClient, SDB]):
    def __init__(
        self, supervisor: Supervisor, options: SnippetClient, misc: SDB
    ) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        self._misc.add_exts(options.extends)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        snippets = self._misc.select(context.filetype, word=context.words)

        def cont() -> Iterator[Completion]:
            for snip in snippets:
                edit = SnippetEdit(new_text=snip["snippet"], grammar=snip["grammar"])
                completion = Completion(
                    source=self._options.short_name,
                    primary_edit=edit,
                    sort_by=snip["prefix"],
                )
                yield completion

        yield tuple(cont())

