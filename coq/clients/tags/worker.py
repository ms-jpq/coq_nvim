from contextlib import suppress
from os import linesep
from os.path import dirname, relpath
from pathlib import Path
from shutil import which
from time import sleep
from typing import AbstractSet, Iterator, Mapping, MutableSet, Optional, Sequence, Tuple

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
from .reconciliate import Tags, reconciliate


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
    doc = Doc(
        text=f"{lc}{pos}:{tag['line']}{rc}{linesep}{tag.context}",
        filetype=context.filetype,
    )
    return doc


class Worker(BaseWorker[PollingClient, None]):
    def __init__(
        self, supervisor: Supervisor, options: PollingClient, misc: None
    ) -> None:
        self._cwd: Optional[Path] = None
        self._db = Database(supervisor.pool)
        super().__init__(supervisor, options=options, misc=misc)
        if which("ctags"):
            supervisor.pool.submit(self._poll)

    def _poll(self) -> None:
        try:
            while self._cwd:
                buf_names = _ls(self._supervisor.nvim)
                tags = reconciliate(self._cwd, paths=buf_names)

                self._db.add(lsd, tags=tags)
                sleep(self._options.polling_interval)
        except Exception as e:
            log.exception("%s", e)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
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
                name = tag["name"]
                if name not in seen:
                    seen.add(name)
                    edit = Edit(new_text=name)
                    cmp = Completion(
                        source=self._options.short_name,
                        tie_breaker=self._options.tie_breaker,
                        label=edit.new_text,
                        primary_edit=edit,
                        kind=tag["kind"] or "",
                        doc=_doc(context, tag=tag),
                    )
                    yield cmp

        yield tuple(cont())

