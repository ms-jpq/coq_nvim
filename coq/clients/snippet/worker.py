from typing import AsyncIterator, Iterator, Sequence

from ...databases.snippets.database import SDB
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import SnippetClient
from ...shared.types import Completion, Context, Doc, SnippetEdit


class Worker(BaseWorker[SnippetClient, SDB]):
    async def work(self, context: Context) -> AsyncIterator[Sequence[Completion]]:
        match = context.words or context.syms
        snippets = await self._misc.select(
            self._supervisor.options,
            filetype=context.filetype,
            word=match,
            limitless=context.manual,
        )

        def cont() -> Iterator[Completion]:
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

        yield tuple(cont())

