from asyncio import as_completed
from locale import strxfrm
from os import X_OK, access
from os.path import join, sep
from pathlib import Path
from typing import AbstractSet, AsyncIterator, Iterator

from std2.asyncio import run_in_executor

from ...shared.parse import lower
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context, Edit


def _p_lhs(lhs: str) -> str:
    for sym in ("..", ".", "~"):
        if lhs.endswith(sym):
            return sym
    else:
        return ""


def _segments(line: str) -> Iterator[str]:
    segments = line.split(sep)
    if len(segments) > 1:
        *rest, front = reversed(segments)
        lhs = _p_lhs(front)
        segs = (*rest, lhs)
        for idx in range(1, len(segs) + 1):
            yield sep.join(reversed(segs[:idx]))


def parse(base: Path, line: str) -> Iterator[str]:
    segments = reversed(tuple(_segments(line)))
    for segment in segments:
        e = Path(segment).expanduser()
        entire = e if e.is_absolute() else base / e
        if entire.is_dir() and access(entire, mode=X_OK):
            for path in entire.iterdir():
                term = sep if path.is_dir() else ""
                yield join(segment, path.name) + term
            break
        else:
            lft, go, rhs = segment.rpartition(sep)
            assert go
            lhs = lft + go
            l = Path(lhs).expanduser()
            left = l if l.is_absolute() else base / l
            if left.is_dir() and access(left, mode=X_OK):
                for path in left.iterdir():
                    if path.name.startswith(rhs):
                        term = sep if path.is_dir() else ""
                        yield join(lhs, path.name) + term
            break


async def _parse(base: Path, line: str) -> AbstractSet[str]:
    def cont() -> AbstractSet[str]:
        return {*parse(base, line=line)}

    return await run_in_executor(cont)


class Worker(BaseWorker[BaseClient, None]):
    async def work(self, context: Context) -> AsyncIterator[Completion]:
        line = context.line_before + context.words_after
        base_paths = {Path(context.filename).parent, Path(context.cwd)}

        for co in as_completed(_parse(p, line=line) for p in base_paths):
            for new_text in await co:
                edit = Edit(new_text=new_text)
                completion = Completion(
                    source=self._options.short_name,
                    tie_breaker=self._options.tie_breaker,
                    label=edit.new_text,
                    sort_by=strxfrm(lower(edit.new_text)),
                    primary_edit=edit,
                )
                yield completion

