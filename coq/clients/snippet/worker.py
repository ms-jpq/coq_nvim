from typing import AsyncIterator

from ...databases.snippets.database import SDB
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import SnippetClient
from ...shared.sql import BIGGEST_INT
from ...shared.types import Completion, Context, Doc, SnippetEdit
from ...snippets.artifacts import SNIPPETS


class Worker(BaseWorker[SnippetClient, SDB]):
    def __init__(
        self, supervisor: Supervisor, options: SnippetClient, misc: SDB
    ) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        self._misc.add_exts(SNIPPETS.extends)

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        match = context.words or context.syms
        snippets = await self._misc.select(
            self._supervisor.options,
            filetype=context.filetype,
            word=match,
            limit=BIGGEST_INT
            if context.manual
            else self._supervisor.options.max_results,
        )

        for snip in snippets:
            edit = SnippetEdit(
                new_text=snip["snippet"],
                grammar=snip["grammar"],
            )
            label = (
                (snip["label"] or edit.new_text or " ")
                .splitlines()[0]
                .strip()
                .replace("\t", "  ")
            )
            doc = Doc(
                text=snip["doc"] or edit.new_text,
                syntax="",
            )
            completion = Completion(
                source=self._options.short_name,
                tie_breaker=self._options.tie_breaker,
                primary_edit=edit,
                sort_by=snip["prefix"],
                label=label,
                doc=doc,
                kind=snip["prefix"],
            )
            yield completion

