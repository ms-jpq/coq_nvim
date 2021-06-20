from typing import Iterator, Sequence

from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import SnippetClient
from ...shared.types import Completion, Context, SnippetEdit
from .database import Database


class Worker(BaseWorker[SnippetClient, None]):
    def __init__(
        self, supervisor: Supervisor, options: SnippetClient, misc: None
    ) -> None:
        self._db = Database(supervisor.pool)
        self._db.add_exts(options.extends)
        super().__init__(supervisor, options=options, misc=misc)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        snippets = self._db.select(context.filetype, word=context.words)

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

