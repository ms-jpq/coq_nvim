from asyncio import Task, as_completed, create_task, sleep
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
)

from pynvim_pp.logging import suppress_and_log
from std2 import anext
from std2.asyncio import cancel
from std2.itertools import chunk

from ...lsp.requests.completion import comp_lsp
from ...lsp.types import LSPcomp
from ...shared.context import cword_before
from ...shared.fuzzy import multi_set_ratio
from ...shared.parse import lower
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import LSPClient, MatchOptions
from ...shared.sql import BIGGEST_INT
from ...shared.timeit import timeit
from ...shared.types import Completion, Context, Edit, SnippetEdit
from ..cache.worker import CacheWorker, sanitize_cached

_CACHE_PERIOD = 1 / 100
_CACHE_CHUNK = 9


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


@dataclass(frozen=True)
class _LocalCache:
    pre: MutableMapping[Optional[str], Tuple[Iterator[Completion], int]] = field(
        default_factory=dict
    )
    post: MutableMapping[Optional[str], MutableSequence[Completion]] = field(
        default_factory=dict
    )


class Worker(BaseWorker[LSPClient, None]):
    def __init__(self, supervisor: Supervisor, options: LSPClient, misc: None) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        self._cache = CacheWorker(supervisor)
        self._local_cached = _LocalCache()
        self._poll_task: Optional[Task] = None
        self._max_results = self._supervisor.match.max_results

    def _request(
        self, context: Context, cached_clients: AbstractSet[str]
    ) -> AsyncIterator[LSPcomp]:
        return comp_lsp(
            short_name=self._options.short_name,
            always_on_top=self._options.always_on_top,
            weight_adjust=self._options.weight_adjust,
            context=context,
            chunk=self._max_results * 2,
            clients=set() if context.manual else cached_clients,
        )

    async def _poll(self) -> None:
        with suppress_and_log(), timeit("LSP CACHE"):
            acc = {**self._local_cached.post}
            await self._cache.set_cache(acc)
            await sleep(_CACHE_PERIOD)

            for client, (comps, _) in self._local_cached.pre.items():
                for chunked in chunk(comps, n=_CACHE_CHUNK):
                    await self._cache.set_cache({client: chunked})
                    await sleep(_CACHE_PERIOD)

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        poll = self._poll_task
        self._poll_task = None

        if poll:
            await cancel(poll)

        async with self._work_lock:
            limit = BIGGEST_INT if context.manual else self._max_results

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
                row, col = context.position
                cursors = (col, context.utf16_col)
                acc = {**self._local_cached.pre}
                self._local_cached.pre.clear()

                for client, (cached_items, length) in acc.items():
                    items = (
                        cached
                        for item in cached_items
                        if (
                            cached := sanitize_cached(
                                row, cursors=cursors, comp=item, sort_by=None
                            )
                        )
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

            seen = 0
            try:
                async for src, lsp_comps in stream():
                    if seen >= limit:
                        break

                    acc = self._local_cached.post.setdefault(lsp_comps.client, [])

                    if lsp_comps.local_cache and lsp_comps.length:
                        self._local_cached.pre[lsp_comps.client] = (
                            lsp_comps.items,
                            lsp_comps.length,
                        )

                    for comp in lsp_comps.items:
                        if src is _Src.from_db:
                            seen += 1
                            yield comp
                        else:
                            acc.append(comp)
                            if _use_comp(
                                self._supervisor.match,
                                context=context,
                                sort_by=comp.sort_by,
                                edit=comp.primary_edit,
                            ):
                                seen += 1
                                yield comp
            finally:
                self._poll_task = create_task(self._poll())
