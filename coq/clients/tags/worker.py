from asyncio import gather
from contextlib import suppress
from os import linesep, sep
from os.path import commonpath, relpath
from pathlib import Path, PurePath
from shutil import which
from typing import (
    AbstractSet,
    AsyncIterator,
    Iterable,
    Iterator,
    Mapping,
    MutableSet,
    Tuple,
)

from pynvim.api.nvim import Nvim, NvimError
from pynvim_pp.api import buf_name, get_cwd, list_bufs
from pynvim_pp.lib import async_call, go
from std2.asyncio import run_in_executor
from std2.pathlib import is_relative_to

from ...databases.tags.database import CTDB
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import TagsClient
from ...shared.timeit import timeit
from ...shared.types import Completion, Context, Doc, Edit
from ...tags.parse import parse, run
from ...tags.types import Tag


async def _ls(nvim: Nvim) -> Tuple[Path, AbstractSet[str]]:
    def c1() -> Iterator[str]:
        for buf in list_bufs(nvim, listed=True):
            with suppress(NvimError):
                filename = buf_name(nvim, buf=buf)
                yield filename

    def c2() -> Tuple[Path, AbstractSet[str]]:
        cwd = Path(get_cwd(nvim))
        return cwd, {*c1()}

    return await async_call(nvim, c2)


async def _mtimes(cwd: Path, paths: AbstractSet[str]) -> Mapping[str, float]:
    def c1() -> Iterable[Tuple[Path, float]]:
        for path in map(Path, paths):
            if is_relative_to(path, cwd):
                with suppress(FileNotFoundError):
                    stat = path.stat()
                    yield path, stat.st_mtime

    c2 = lambda: {str(key): val for key, val in c1()}
    return await run_in_executor(c2)


def _doc(client: TagsClient, context: Context, tag: Tag) -> Doc:
    def cont() -> Iterator[str]:
        lc, rc = context.comment
        path, cfn = PurePath(tag["path"]), PurePath(context.filename)
        if path == cfn:
            pos = "."
        elif path.anchor != cfn.anchor or PurePath(commonpath((path, cfn))) in {
            PurePath(sep),
            Path.home(),
        }:
            pos = str(path)
        else:
            pos = relpath(path, cfn.parent)

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

        yield tag["pattern"]

    doc = Doc(
        text="".join(cont()),
        syntax=context.filetype,
    )
    return doc


class Worker(BaseWorker[TagsClient, CTDB]):
    def __init__(self, supervisor: Supervisor, options: TagsClient, misc: CTDB) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        if which("ctags"):
            go(supervisor.nvim, aw=self._poll())

    async def _poll(self) -> None:
        while True:
            with timeit("IDLE :: TAGS"):
                (cwd, buf_names), existing = await gather(
                    _ls(self._supervisor.nvim), self._misc.paths()
                )
                paths = buf_names | existing.keys()
                mtimes = await _mtimes(cwd, paths=paths)
                query_paths = tuple(
                    path
                    for path, mtime in mtimes.items()
                    if mtime > existing.get(path, 0)
                )
                raw = await run(*query_paths) if query_paths else ""
                new = parse(mtimes, raw=raw)
                dead = existing.keys() - mtimes.keys()
                await self._misc.reconciliate(dead, new=new)

            async with self._supervisor.idling:
                await self._supervisor.idling.wait()

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        row, _ = context.position
        match = context.words or (context.syms if self._options.match_syms else "")
        tags = await self._misc.select(
            self._supervisor.options,
            filename=context.filename,
            line_num=row,
            word=match,
            limitless=context.manual,
        )

        seen: MutableSet[str] = set()
        for tag in tags:
            name = tag["name"]
            if name not in seen:
                seen.add(name)
                edit = Edit(new_text=name)
                cmp = Completion(
                    source=self._options.short_name,
                    tie_breaker=self._options.tie_breaker,
                    label=edit.new_text,
                    sort_by=name,
                    primary_edit=edit,
                    kind=tag["kind"],
                    doc=_doc(self._options, context=context, tag=tag),
                )
                yield cmp

