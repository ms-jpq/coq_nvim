from contextlib import suppress
from os.path import dirname, relpath
from pathlib import Path, PurePath
from shutil import which
from string import Template
from subprocess import DEVNULL, CalledProcessError, check_output
from time import sleep
from typing import Iterator, Mapping, Sequence, Tuple

from pynvim.api.nvim import Nvim, NvimError
from pynvim_pp.api import buf_filetype, buf_name, list_bufs
from pynvim_pp.lib import threadsafe_call
from pynvim_pp.logging import log

from ...consts import TIMEOUT
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import PollingClient
from ...shared.types import Completion, Context, Doc, Edit
from .database import Database
from .parser import parse
from .types import Section

_DOC_T = """
$lc$pos$rc
$tag
"""

_DOC = Template(_DOC_T.strip())


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


def _check_etags(paths: Sequence[PurePath]) -> Iterator[Section]:
    try:
        raw = (
            check_output(
                ("ctags", "-e", "-o", "-", *paths),
                text=True,
                timeout=TIMEOUT,
                stdin=DEVNULL,
                stderr=DEVNULL,
            )
            if paths
            else ""
        )
    except CalledProcessError:
        raw = ""

    parsed = parse(raw)
    return parsed


class Worker(BaseWorker[PollingClient, None]):
    def __init__(
        self, supervisor: Supervisor, options: PollingClient, misc: None
    ) -> None:
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
                parsed = _check_etags(paths)
                self._db.add(lsd, sections=parsed)
                sleep(self._options.polling_interval)
        except Exception as e:
            log.exception("%s", e)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        lc, rc = context.comment
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
            for tag in tags:
                pos = (
                    "."
                    if tag["filename"] == context.filename
                    else relpath(tag["filename"], dirname(context.filename))
                )
                doc_txt = _DOC.substitute(
                    lc=lc,
                    rc=rc,
                    pos=f"{pos}:{tag['line_num']}",
                    tag=tag["text"].strip(),
                )
                edit = Edit(new_text=tag["name"])
                doc = Doc(
                    text=doc_txt,
                    filetype=context.filetype,
                )
                cmp = Completion(
                    source=self._options.short_name,
                    tie_breaker=self._options.tie_breaker,
                    primary_edit=edit,
                    doc=doc,
                )
                yield cmp

        yield tuple(cont())

