from contextlib import suppress
from os import linesep
from os.path import dirname, relpath
from pathlib import Path
from shutil import which
from threading import Lock
from time import sleep
from typing import AbstractSet, Iterator, MutableSet, Optional, Sequence

from pynvim.api.nvim import Nvim, NvimError
from pynvim_pp.api import buf_name, list_bufs
from pynvim_pp.lib import threadsafe_call
from pynvim_pp.logging import log

from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import PollingClient
from ...shared.types import Completion, Context, Doc, Edit
from .database import Database
from .parser import Tag
from .reconciliate import reconciliate


def _ls(nvim: Nvim) -> AbstractSet[str]:
    def cont() -> Iterator[str]:
        for buf in list_bufs(nvim, listed=True):
            with suppress(NvimError):
                filename = buf_name(nvim, buf=buf)
                yield filename

    return {*threadsafe_call(nvim, lambda: tuple(cont()))}


def _doc(context: Context, tag: Tag) -> Doc:
    lc, rc = context.comment
    pos = (
        "."
        if tag["path"] == context.filename
        else relpath(tag["path"], dirname(context.filename))
    )

    def cont() -> Iterator[str]:
        yield f"{lc}{pos}:{tag['line']}{rc}"
        yield linesep
        if tag["scope"]:
            yield tag["scope"] or ""
            if tag["scopeKind"]:
                yield " -> "
                yield tag["scopeKind"] or ""
                if tag["roles"]:
                    yield " -> "
                    yield tag["roles"] or ""
            yield linesep
        yield tag["pattern"]

    doc = Doc(
        text="".join(cont()),
        filetype=context.filetype,
    )
    return doc


def _cmp(client: PollingClient, context: Context, tag: Tag) -> Completion:
    edit = Edit(new_text=tag["name"])
    _, ref_sep, ref = (tag.get("typeref") or "").partition(":")
    kind = ref + ref_sep + (tag["kind"] or "")

    cmp = Completion(
        source=client.short_name,
        tie_breaker=client.tie_breaker,
        label=edit.new_text,
        primary_edit=edit,
        kind=kind,
        doc=_doc(context, tag=tag),
    )
    return cmp


class Worker(BaseWorker[PollingClient, None]):
    def __init__(
        self, supervisor: Supervisor, options: PollingClient, misc: None
    ) -> None:
        self._cwd: Optional[Path] = None
        self._lock = Lock()
        self._db = Database(supervisor.pool)
        super().__init__(supervisor, options=options, misc=misc)
        if which("ctags"):
            supervisor.pool.submit(self._poll)

    def _poll(self) -> None:
        try:
            while True:
                with self._lock:
                    cwd = self._cwd

                if cwd:
                    buf_names = _ls(self._supervisor.nvim)
                    tags = reconciliate(cwd, paths=buf_names)
                    self._db.add(tags)
                sleep(self._options.polling_interval)
        except Exception as e:
            log.exception("%s", e)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        with self._lock:
            self._cwd = context.cwd

        row, _ = context.position
        match = context.words or (context.syms if self._options.match_syms else "")
        tags = self._db.select(
            self._supervisor.options,
            filetype=context.filetype,
            filename=context.filename,
            line_num=row,
            word=match,
        )

        def cont() -> Iterator[Completion]:
            seen: MutableSet[str] = set()
            for tag in tags:
                if tag["name"] not in seen:
                    seen.add(tag["name"])
                    yield _cmp(self._options, context=context, tag=tag)

        yield tuple(cont())

