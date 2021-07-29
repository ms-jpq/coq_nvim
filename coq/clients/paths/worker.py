from asyncio import as_completed
from itertools import islice
from os import X_OK, access
from os.path import expanduser, expandvars, join, normcase, normpath, sep, split
from pathlib import Path
from typing import AbstractSet, AsyncIterator, Iterator, MutableSet, Sequence, Tuple

from std2.asyncio import run_in_executor

from ...shared.parse import is_word, lower
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.sql import BIGGEST_INT
from ...shared.types import Completion, Context, Edit


def _p_lhs(lhs: str) -> str:
    for sym in ("..", ".", "~"):
        if lhs.endswith(sym):
            return sym
    else:
        if lhs.endswith("}"):
            _, s, r = lhs.rpartition("${")
            return s + r if s else ""
        else:
            _, s, r = lhs.rpartition("$")
            return s + r if s else ""


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


def _sort_by(segment: str, unifying_chars: AbstractSet[str]) -> str:
    def cont() -> Iterator[str]:
        seen_syms = False
        for char in reversed(segment):
            if is_word(char, unifying_chars=unifying_chars):
                if seen_syms:
                    break
                else:
                    yield char
            else:
                yield char
                seen_syms = True

    return "".join(reversed(tuple(cont())))


def parse(
    unifying_chars: AbstractSet[str], base: Path, line: str
) -> Iterator[Tuple[str, str]]:
    segments = reversed(tuple(_segments(line)))
    for segment in segments:
        sort_by = _sort_by(segment, unifying_chars=unifying_chars)

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
                    yield line, sort_by
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
                        is_lower = lower(rhs) == rhs

                        for path in left.iterdir():
                            l_match = (
                                lower(path.name) if is_lower else normcase(path.name)
                            )
                            if l_match.startswith(rhs):
                                term = sep if path.is_dir() else ""
                                name = rhs + path.name[len(rhs) :]
                                line = _join(lseg, name) + term
                                yield line, sort_by
                        return


async def _parse(
    base: Path, line: str, limit: int, unifying_chars: AbstractSet[str]
) -> AbstractSet[Tuple[str, str]]:
    def cont() -> AbstractSet[Tuple[str, str]]:
        return {*islice(parse(unifying_chars, base=base, line=line), limit)}

    return await run_in_executor(cont)


class Worker(BaseWorker[BaseClient, None]):
    async def work(self, context: Context) -> AsyncIterator[Sequence[Completion]]:
        line = context.line_before + context.words_after
        base_paths = {Path(context.filename).parent, Path(context.cwd)}

        limit = BIGGEST_INT if context.manual else self._supervisor.options.max_results
        aw = tuple(
            _parse(
                p,
                line=line,
                limit=limit,
                unifying_chars=self._supervisor.options.unifying_chars,
            )
            for p in base_paths
        )
        seen: MutableSet[str] = set()

        for co in as_completed(aw):
            seq = await co

            def cont() -> Iterator[Completion]:
                for new_text, sort_by in seq:
                    if len(seen) >= limit:
                        break
                    elif new_text not in seen:
                        seen.add(new_text)
                        edit = Edit(new_text=new_text)
                        completion = Completion(
                            source=self._options.short_name,
                            tie_breaker=self._options.tie_breaker,
                            label=edit.new_text,
                            sort_by=sort_by,
                            primary_edit=edit,
                        )
                        yield completion

            yield tuple(cont())
