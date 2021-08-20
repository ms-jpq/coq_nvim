from asyncio import as_completed
from itertools import islice
from os import X_OK, access
from os.path import (
    altsep,
    curdir,
    expanduser,
    expandvars,
    join,
    normcase,
    normpath,
    pardir,
    sep,
    split,
)
from pathlib import Path, PurePath
from typing import AbstractSet, AsyncIterator, Iterator, MutableSet, Tuple

from std2.asyncio import run_in_executor

from ...shared.fuzzy import quick_ratio
from ...shared.parse import is_word, lower
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import PathsClient
from ...shared.sql import BIGGEST_INT
from ...shared.types import Completion, Context, Edit, Extern


def _p_lhs(lhs: str) -> str:
    for sym in (pardir, curdir, "~"):
        if lhs.endswith(sym):
            return sym
    else:
        if lhs.endswith("}"):
            _, s, r = lhs.rpartition("${")
            return s + r if s else ""
        else:
            _, s, r = lhs.rpartition("$")
            return s + r if s else ""


def separate(seps: AbstractSet[str], line: str) -> Iterator[str]:
    if not seps:
        yield line
    else:
        sep = next(iter(seps))
        for l in line.split(sep):
            yield from separate(seps - {sep}, l)


def _segments(seps: AbstractSet[str], line: str) -> Iterator[str]:
    segments = tuple(separate(seps, line=line))
    if len(segments) > 1:
        *rest, front = reversed(segments)
        lhs = _p_lhs(front)
        segs = (*rest, lhs)
        for idx in range(1, len(segs) + 1):
            yield sep.join(reversed(segs[:idx]))


def _join(lhs: str, rhs: str) -> str:
    l, r = split(lhs)
    return join(l, normpath(join(r, rhs)))


def parse(
    seps: AbstractSet[str],
    look_ahead: int,
    fuzzy_cutoff: float,
    base: Path,
    line: str,
) -> Iterator[Tuple[PurePath, str]]:
    segments = reversed(tuple(_segments(seps, line=line)))
    for segment in segments:

        s1 = segment
        s2 = expanduser(s1)
        s3 = expandvars(s2)

        for s0 in (s1, s2, s3):
            p = Path(s0)
            entire = p if p.is_absolute() else base / p
            if entire.is_dir() and access(entire, mode=X_OK):
                for path in entire.iterdir():
                    term = sep if path.is_dir() else ""
                    line = _join(segment, path.name) + term
                    yield path, line
                return

            else:
                lft, go, rhs = s0.rpartition(sep)
                if go:
                    lp, sp, _ = segment.rpartition(sep)
                    lseg = lp + sp

                    lhs = lft + go
                    p = Path(lhs)
                    left = p if p.is_absolute() else base / p
                    if left.is_dir() and access(left, mode=X_OK):
                        for path in left.iterdir():
                            ratio = quick_ratio(
                                rhs, lower(path.name), look_ahead=look_ahead
                            )
                            if ratio >= fuzzy_cutoff and len(
                                path.name
                            ) + look_ahead >= len(rhs):
                                term = sep if path.is_dir() else ""
                                line = _join(lseg, path.name) + term
                                yield path, line
                        return


async def _parse(
    base: Path,
    line: str,
    seps: AbstractSet[str],
    limit: int,
    look_ahead: int,
    fuzzy_cutoff: float,
) -> AbstractSet[Tuple[PurePath, str]]:
    def cont() -> AbstractSet[Tuple[PurePath, str]]:
        return {
            *islice(
                parse(
                    seps,
                    look_ahead=look_ahead,
                    fuzzy_cutoff=fuzzy_cutoff,
                    base=base,
                    line=line,
                ),
                limit,
            )
        }

    return await run_in_executor(cont)


def sort_by(unifying_chars: AbstractSet[str], new_text: str) -> str:
    def cont() -> Iterator[str]:
        seen_syms = False
        for idx, char in enumerate(reversed(new_text)):
            if is_word(char, unifying_chars=unifying_chars):
                if seen_syms:
                    break
                else:
                    yield char
            else:
                yield char
                if not idx and char == sep:
                    pass
                else:
                    seen_syms = True

    sort_by = "".join(reversed(tuple(cont())))
    return sort_by


class Worker(BaseWorker[PathsClient, None]):
    def __init__(
        self, supervisor: Supervisor, options: PathsClient, misc: None
    ) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        seps = {sep, altsep} if altsep else {sep}
        self._seps = {sep for sep in options.path_seps if sep in seps} or seps

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        line = context.line_before + context.words_after
        base_paths = {Path(context.filename).parent, Path(context.cwd)}

        limit = BIGGEST_INT if context.manual else self._supervisor.options.max_results
        aw = tuple(
            _parse(
                p,
                line=line,
                seps=self._seps,
                limit=limit,
                look_ahead=self._supervisor.options.look_ahead,
                fuzzy_cutoff=self._supervisor.options.fuzzy_cutoff,
            )
            for p in base_paths
        )
        seen: MutableSet[str] = set()

        for co in as_completed(aw):
            seq = await co

            for path, new_text in seq:
                if len(seen) >= limit:
                    break
                elif new_text not in seen:
                    seen.add(new_text)
                    edit = Edit(new_text=new_text)
                    completion = Completion(
                        source=self._options.short_name,
                        priority=self._options.priority,
                        label=edit.new_text,
                        sort_by=sort_by(
                            self._supervisor.options.unifying_chars, new_text=new_text
                        ),
                        primary_edit=edit,
                        extern=(Extern.path, normcase(path)),
                    )
                    yield completion
