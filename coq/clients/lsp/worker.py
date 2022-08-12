from asyncio import Task, as_completed, sleep
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import (
    AbstractSet,
    AsyncIterator,
    Iterator,
    MutableMapping,
    MutableSequence,
    Optional,
    Tuple,
    cast,
)

from pynvim_pp.lib import go
from pynvim_pp.logging import with_suppress
from std2 import anext
from std2.asyncio import cancel
from std2.itertools import chunk

from ...lsp.requests.completion import comp_lsp
from ...lsp.types import LSPcomp
from ...shared.fuzzy import multi_set_ratio
from ...shared.parse import lower
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient, MatchOptions
from ...shared.sql import BIGGEST_INT
from ...shared.timeit import timeit
from ...shared.trans import cword_before
from ...shared.types import Completion, Context, Edit, SnippetEdit
from ..cache.worker import CacheWorker, sanitize_cached


class _Src(Enum):
    from_db = auto()
    from_stored = auto()
    from_query = auto()


def _use_comp(match: MatchOptions, context: Context, sort_by: str, edit: Edit) -> bool:
    cword = cword_before(
        match.unifying_chars,
        lower=True,
        context=context,
        sort_by=sort_by,
    )
    if len(sort_by) + match.look_ahead >= len(cword):
        ratio = multi_set_ratio(
            cword,
            lower(sort_by),
            look_ahead=match.look_ahead,
        )
        use = ratio >= match.fuzzy_cutoff and (
            isinstance(edit, SnippetEdit) or not cword.startswith(edit.new_text)
        )
        return use
    else:
        return False


def _fast_comp(
    look_ahead: int,
    lower_word: str,
    lower_word_prefix: str,
    sort_by: str,
) -> bool:
    if not lower_word_prefix:
        return True
    else:
        lo = lower(sort_by)
        return lo[:look_ahead] == lower_word_prefix and not lower_word.startswith(lo)


@dataclass(frozen=True)
class _LocalCache:
    pre: MutableMapping[Optional[str], Tuple[Iterator[Completion], int]] = field(
        default_factory=dict
    )
    post: MutableMapping[Optional[str], MutableSequence[Completion]] = field(
        default_factory=dict
    )


class Worker(BaseWorker[BaseClient, None]):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: None) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        self._cache = CacheWorker(supervisor)
        self._local_cached = _LocalCache()
        self._poll_task: Optional[Task] = None

    def _request(
        self, context: Context, cached_clients: AbstractSet[str]
    ) -> AsyncIterator[LSPcomp]:
        return comp_lsp(
            self._supervisor.nvim,
            short_name=self._options.short_name,
            weight_adjust=self._options.weight_adjust,
            context=context,
            clients=set() if context.manual else cached_clients,
        )

    async def _poll(self) -> None:
        with with_suppress():
            acc = {**self._local_cached.post}
            await self._cache.set_cache(acc)
            await sleep(0)

            for client, (comps, _) in self._local_cached.pre.items():
                for chunked in chunk(comps, n=9):
                    await self._cache.set_cache({client: chunked})
                    await sleep(0)

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        poll = self._poll_task
        self._poll_task = None

        if poll:
            await cancel(poll)

        async with self._work_lock:
            limit = (
                BIGGEST_INT if context.manual else self._supervisor.match.max_results
            )
            fast_limit = self._supervisor.match.max_results * 3
            lower_word_prefix = context.l_words_before[
                : self._supervisor.match.look_ahead
            ]

            use_cache, cached_clients, cached = self._cache.apply_cache(context)
            if not use_cache:
                self._local_cached.pre.clear()
                self._local_cached.post.clear()

            lsp_stream = self._request(context, cached_clients=cached_clients)

            async def db() -> Tuple[_Src, LSPcomp]:
                items, length = await cached
                return _Src.from_db, LSPcomp(
                    client=None, local_cache=False, items=items, length=length
                )

            async def lsp() -> Optional[Tuple[_Src, LSPcomp]]:
                if comps := await anext(lsp_stream, None):
                    return _Src.from_query, comps
                else:
                    return None

            async def stream() -> AsyncIterator[Tuple[_Src, LSPcomp]]:
                acc = {**self._local_cached.pre}
                self._local_cached.pre.clear()

                for client, (cached_items, length) in acc.items():
                    items = (
                        sanitize_cached(item, sort_by=None) for item in cached_items
                    )
                    yield _Src.from_stored, LSPcomp(
                        client=client, local_cache=True, items=items, length=length
                    )

                for co in as_completed((db(), lsp())):
                    if comps := await co:
                        yield comps

                if context.manual or not use_cache:
                    async for lsp_comps in lsp_stream:
                        yield _Src.from_query, lsp_comps

            try:
                seen = 0
                async for src, lsp_comps in stream():
                    if lsp_comps.local_cache:
                        if lsp_comps.length:
                            self._local_cached.pre[lsp_comps.client] = (
                                lsp_comps.items,
                                lsp_comps.length,
                            )

                    for comp in lsp_comps.items:
                        if src is _Src.from_db:
                            if seen < limit:
                                seen += 1
                                yield comp
                        else:
                            acc = self._local_cached.post.setdefault(
                                lsp_comps.client, []
                            )
                            acc.append(comp)

                            fast_search = lsp_comps.length > fast_limit
                            if seen < limit:
                                if (
                                    _fast_comp(
                                        self._supervisor.match.look_ahead,
                                        lower_word=context.l_words_before,
                                        lower_word_prefix=lower_word_prefix,
                                        sort_by=comp.sort_by,
                                    )
                                    if fast_search
                                    else _use_comp(
                                        self._supervisor.match,
                                        context=context,
                                        sort_by=comp.sort_by,
                                        edit=comp.primary_edit,
                                    )
                                ):
                                    seen += 1
                                    yield comp
            finally:
                self._poll_task = cast(Task, go(self._supervisor.nvim, aw=self._poll()))
