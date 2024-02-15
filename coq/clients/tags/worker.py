from asyncio import create_task, gather
from contextlib import suppress
from os import linesep
from os.path import normcase
from pathlib import Path, PurePath
from string import capwords
from typing import (
    AbstractSet,
    AsyncIterator,
    Iterable,
    Iterator,
    Mapping,
    MutableSet,
    Tuple,
)

from pynvim_pp.atomic import Atomic
from pynvim_pp.buffer import Buffer
from pynvim_pp.logging import suppress_and_log
from pynvim_pp.rpc_types import NvimError
from std2.asyncio import to_thread

from ...paths.show import fmt_path
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import TagsClient
from ...shared.timeit import timeit
from ...shared.types import Completion, Context, Doc, Edit
from ...tags.parse import parse, run
from ...tags.types import Tag
from .db.database import CTDB


async def _ls() -> AbstractSet[str]:
    try:
        bufs = await Buffer.list(listed=True)
        atomic = Atomic()

        for buf in bufs:
            atomic.buf_get_name(buf)
        names = await atomic.commit(str)
    except NvimError:
        return set()
    else:
        return {*names}


async def _mtimes(paths: AbstractSet[str]) -> Mapping[str, float]:
    def c1() -> Iterable[Tuple[Path, float]]:
        for path in map(Path, paths):
            with suppress(OSError):
                stat = path.stat()
                yield path, stat.st_mtime

    c2 = lambda: {normcase(key): val for key, val in c1()}
    return await to_thread(c2)


def _doc(client: TagsClient, context: Context, tag: Tag) -> Doc:
    def cont() -> Iterator[str]:
        lc, rc = context.comment
        path = PurePath(tag["path"])
        pos = fmt_path(
            context.cwd, path=path, is_dir=False, current=PurePath(context.filename)
        )

        yield lc
        yield pos
        yield ":"
        yield str(tag["line"])
        yield rc
        yield linesep

        scope_kind = tag["scopeKind"] or None
        scope = tag["scope"] or None

        if scope_kind and scope:
            yield lc
            yield scope_kind
            yield client.path_sep
            yield scope
            yield client.parent_scope
            yield rc
            yield linesep
        elif scope_kind:
            yield lc
            yield scope_kind
            yield client.parent_scope
            yield rc
            yield linesep
        elif scope:
            yield lc
            yield scope
            yield client.parent_scope
            yield rc
            yield linesep

        access = tag["access"] or None
        _, _, ref = (tag.get("typeref") or "").partition(":")
        if access and ref:
            yield lc
            yield access
            yield client.path_sep
            yield tag["kind"]
            yield client.path_sep
            yield ref
            yield rc
            yield linesep
        elif access:
            yield lc
            yield access
            yield client.path_sep
            yield tag["kind"]
            yield rc
            yield linesep
        elif ref:
            yield lc
            yield tag["kind"]
            yield client.path_sep
            yield ref
            yield rc
            yield linesep

        yield tag["pattern"] or tag["name"]

    doc = Doc(
        text="".join(cont()),
        syntax=context.filetype,
    )
    return doc


class Worker(BaseWorker[TagsClient, CTDB]):
    def __init__(
        self, supervisor: Supervisor, options: TagsClient, misc: Tuple[Path, CTDB]
    ) -> None:
        self._exec, db = misc
        super().__init__(supervisor, options=options, misc=db)
        create_task(self._poll())

    async def _poll(self) -> None:
        while True:
            with suppress_and_log():
                with timeit("IDLE :: TAGS"):
                    buf_names, existing = await gather(_ls(), self._misc.paths())
                    paths = buf_names | existing.keys()
                    mtimes = await _mtimes(paths)
                    query_paths = tuple(
                        path
                        for path, mtime in mtimes.items()
                        if mtime > existing.get(path, 0)
                    )
                    raw = await run(self._exec, *query_paths) if query_paths else ""
                    new = parse(mtimes, raw=raw)
                    dead = existing.keys() - mtimes.keys()
                    await self._misc.reconciliate(dead, new=new)

                async with self._supervisor.idling:
                    await self._supervisor.idling.wait()

    async def swap(self, cwd: PurePath) -> None:
        await self._misc.swap(cwd)

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        async with self._work_lock:
            row, _ = context.position
            tags = await self._misc.select(
                self._supervisor.match,
                filename=context.filename,
                line_num=row,
                word=context.words,
                sym=context.syms,
                limitless=context.manual,
            )

            seen: MutableSet[str] = set()
            for tag in tags:
                name = tag["name"]
                if name not in seen:
                    seen.add(name)
                    edit = Edit(new_text=name)
                    kind = capwords(tag["kind"])
                    cmp = Completion(
                        source=self._options.short_name,
                        always_on_top=self._options.always_on_top,
                        weight_adjust=self._options.weight_adjust,
                        label=edit.new_text,
                        sort_by=name,
                        primary_edit=edit,
                        adjust_indent=False,
                        kind=kind,
                        doc=_doc(self._options, context=context, tag=tag),
                        icon_match=kind,
                    )
                    yield cmp
