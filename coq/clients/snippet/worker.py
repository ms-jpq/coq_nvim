from typing import Iterator, Sequence

from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context, SnippetEdit
from .database import Database


class Worker(BaseWorker[BaseClient, None]):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: None) -> None:
        self._db = Database(supervisor.pool, location=":memory:")
        super().__init__(supervisor, options=options, misc=misc)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        snippets = self._db.select(context.words_before, filetype=context.filetype)

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

