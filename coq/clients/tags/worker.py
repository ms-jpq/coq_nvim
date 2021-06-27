from contextlib import suppress
from os import linesep
from os.path import dirname, relpath
from pathlib import Path
from shutil import which
from time import sleep
from typing import Iterator, Mapping, MutableSet, Optional, Sequence, Tuple

from pynvim.api.nvim import Nvim, NvimError
from pynvim_pp.api import buf_filetype, buf_name, list_bufs
from pynvim_pp.lib import threadsafe_call
from pynvim_pp.logging import log

from ...consts import CLIENTS_DIR
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import PollingClient
from ...shared.types import Completion, Context, Doc, Edit
from .database import Database
from .parser import Tag, parse

_TAGS_DIR = CLIENTS_DIR / "tags"


def _ls(nvim: Nvim) -> Mapping[Path, Tuple[str, float]]:
    def cont() -> Sequence[Tuple[str, str]]:
        def c1() -> Iterator[Tuple[str, str]]:
            for buf in list_bufs(nvim, listed=True):
                with suppress(NvimError):
                    filename = buf_name(nvim, buf=buf)
                    filetype = buf_filetype(nvim, buf=buf)
                    yield filename, filetype

        return tuple(c1())

    def c2() -> Iterator[Tuple[Path, float, str]]:
        lsd = threadsafe_call(nvim, cont)
        for filename, filetype in lsd:
            path = Path(filename).resolve()
            with suppress(FileNotFoundError):
                stat = path.stat()
                yield path, stat.st_mtime, filetype

    return {path: (filetype, mtime) for path, mtime, filetype in c2()}


def _doc(context: Context, tag: Tag) -> Doc:
    lc, rc = context.comment
    pos = (
        "."
        if tag.filename == context.filename
        else relpath(tag.filename, dirname(context.filename))
    )
    doc = Doc(
        text=f"{lc}{pos}:{tag.line_num}{rc}{linesep}{tag.context}",
        filetype=context.filetype,
    )
    return doc


class Worker(BaseWorker[PollingClient, None]):
    def __init__(
        self, supervisor: Supervisor, options: PollingClient, misc: None
    ) -> None:
        self._cwd: Optional[str] = None
        self._db = Database(supervisor.pool)
        super().__init__(supervisor, options=options, misc=misc)
        if which("ctags"):
            supervisor.pool.submit(self._poll)

    def _poll(self) -> None:
        try:
            while True:
                in_db = {
                    Path(file["filename"]): file["mtime"]
                    for file in self._db.ls_files()
                }
                gone = (str(file) for file in in_db.keys() if not file.exists())
                self._db.vaccum(gone)
                lsd = _ls(self._supervisor.nvim)
                paths = tuple(
                    path
                    for path, (_, mtime) in lsd.items()
                    if mtime > in_db.get(path, 0)
                )
                tags = parse(paths)
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
                if tag.name not in seen:
                    seen.add(tag.name)
                    edit = Edit(new_text=tag.name)
                    cmp = Completion(
                        source=self._options.short_name,
                        tie_breaker=self._options.tie_breaker,
                        label=edit.new_text.strip(),
                        primary_edit=edit,
                        kind=tag.kind,
                        doc=_doc(context, tag=tag),
                    )
                    yield cmp

        yield tuple(cont())

