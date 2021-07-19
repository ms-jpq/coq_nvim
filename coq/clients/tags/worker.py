from contextlib import suppress
from os import linesep
from os.path import dirname, relpath
from pathlib import Path
from shutil import which
from typing import AbstractSet, AsyncIterator, Iterator, MutableSet, Tuple

from pynvim.api.nvim import Nvim, NvimError
from pynvim_pp.api import buf_name, get_cwd, list_bufs
from pynvim_pp.lib import async_call, go

from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import TagsClient
from ...shared.types import Completion, Context, Doc, Edit
from .database import Database
from .parser import Tag
from .reconciliate import reconciliate


async def _ls(nvim: Nvim) -> Tuple[Path, AbstractSet[str]]:
    def c1() -> Iterator[str]:
        for buf in list_bufs(nvim, listed=True):
            with suppress(NvimError):
                filename = buf_name(nvim, buf=buf)
                yield filename

    def cont() -> Tuple[Path, AbstractSet[str]]:
        cwd = Path(get_cwd(nvim))
        return cwd, {*c1()}

    return await async_call(nvim, cont)


def _doc(client: TagsClient, context: Context, tag: Tag) -> Doc:
    def cont() -> Iterator[str]:
        lc, rc = context.comment
        pos = (
            "."
            if tag["path"] == context.filename
            else relpath(tag["path"], dirname(context.filename))
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

        yield tag["pattern"]

    doc = Doc(
        text="".join(cont()),
        syntax=context.filetype,
    )
    return doc


class Worker(BaseWorker[TagsClient, None]):
    def __init__(self, supervisor: Supervisor, options: TagsClient, misc: None) -> None:
        self._db = Database(supervisor.pool)
        super().__init__(supervisor, options=options, misc=misc)
        if which("ctags"):
            go(supervisor.nvim, aw=self._poll())

    async def _poll(self) -> None:
        while True:
            async with self._supervisor.idling:
                await self._supervisor.idling.wait()
            cwd, buf_names = await _ls(self._supervisor.nvim)

            tags = await reconciliate(cwd, paths=buf_names)
            await self._db.add(tags)

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        row, _ = context.position
        match = context.words or (context.syms if self._options.match_syms else "")
        tags = await self._db.select(
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

