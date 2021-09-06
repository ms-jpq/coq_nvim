from typing import AsyncIterator

from ...databases.snippets.database import SDB
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import SnippetClient
from ...shared.types import Completion, Context, Doc, SnippetEdit, SnippetGrammar


class Worker(BaseWorker[SnippetClient, SDB]):
    async def work(self, context: Context) -> AsyncIterator[Completion]:
        match = context.words or context.syms
        snippets = await self._misc.select(
            self._supervisor.options,
            filetype=context.filetype,
            word=match,
            limitless=context.manual,
        )

        for snip in snippets:
            edit = SnippetEdit(
                new_text=snip["snippet"],
                grammar=SnippetGrammar[snip["grammar"]],
            )
            label_line, *_ = (snip["label"] or edit.new_text or " ").splitlines()
            label = label_line.strip().expandtabs(2)
            doc = Doc(
                text=snip["doc"] or edit.new_text,
                syntax="",
            )
            completion = Completion(
                source=self._options.short_name,
                weight_adjust=self._options.weight_adjust,
                primary_edit=edit,
                sort_by=snip["prefix"],
                label=label,
                doc=doc,
                kind=snip["prefix"],
                icon_match="Snippet",
            )
            yield completion
