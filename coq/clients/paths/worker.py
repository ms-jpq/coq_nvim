from asyncio import as_completed
from itertools import islice
from locale import strxfrm
from os import X_OK, access
from os.path import join, normpath, sep, split
from pathlib import Path
from typing import AbstractSet, AsyncIterator, Iterator, Tuple

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


def _join(lhs: str, rhs: str) -> str:
    l, r = split(lhs)
    return join(l, normpath(join(r, rhs)))


def parse(base: Path, line: str) -> Iterator[Tuple[str, str]]:
    segments = reversed(tuple(_segments(line)))
    for segment in segments:
        _, ss, sr = segment.rpartition(sep)
        sort_by = ss + sr

        e = Path(segment).expanduser()
        entire = e if e.is_absolute() else base / e
        if entire.is_dir() and access(entire, mode=X_OK):
            for path in entire.iterdir():
                term = sep if path.is_dir() else ""
                line = _join(segment, path.name) + term
                yield line, sort_by
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
                        line = _join(lhs, path.name) + term
                        yield line, sort_by
            break


async def _parse(base: Path, line: str, limit: int) -> AbstractSet[Tuple[str, str]]:
    def cont() -> AbstractSet[Tuple[str, str]]:
        return {*islice(parse(base, line=line), limit)}

    return await run_in_executor(cont)


class Worker(BaseWorker[BaseClient, None]):
    async def work(self, context: Context) -> AsyncIterator[Completion]:
        line = context.line_before + context.words_after
        base_paths = {Path(context.filename).parent, Path(context.cwd)}

        aw = tuple(
            _parse(p, line=line, limit=self._supervisor.options.max_results)
            for p in base_paths
        )
        for co in as_completed(aw):
            for new_text, sort_by in await co:
                edit = Edit(new_text=new_text)
                completion = Completion(
                    source=self._options.short_name,
                    tie_breaker=self._options.tie_breaker,
                    label=edit.new_text,
                    sort_by=strxfrm(lower(sort_by)),
                    primary_edit=edit,
                )
                yield completion

