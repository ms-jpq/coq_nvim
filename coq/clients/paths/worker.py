from asyncio import as_completed
from contextlib import suppress
from itertools import chain, islice
from os import scandir
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
from string import ascii_letters, digits
from typing import (
    AbstractSet,
    AsyncIterator,
    Iterator,
    MutableSequence,
    MutableSet,
    Tuple,
)

from std2.asyncio import run_in_executor
from std2.platform import OS, os
from std2.string import removesuffix

from ...shared.fuzzy import quick_ratio
from ...shared.parse import is_word, lower
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import PathResolution, PathsClient
from ...shared.sql import BIGGEST_INT
from ...shared.types import Completion, Context, Edit, Extern

_DRIVE_LETTERS = {*ascii_letters}
_SH_VAR_CHARS = {*ascii_letters, *digits, "_"}


def p_lhs(os: OS, lhs: str) -> str:
    # TODO -- expand ~user
    for sym in (pardir, curdir, "~"):
        if lhs.endswith(sym):
            return sym
    else:
        if os is OS.windows and lhs.endswith(":"):
            maybe_drive = removesuffix(lhs, suffix=":")[-1:]
            return maybe_drive + ":" if maybe_drive in _DRIVE_LETTERS else ""
        elif os is OS.windows and lhs.endswith("%"):
            _, s, r = removesuffix(lhs, suffix="%").rpartition("%")
            return s + r + s if s and {*r}.issubset(_SH_VAR_CHARS) else ""
        elif lhs.endswith("}"):
            _, s, r = lhs.rpartition("${")
            return (
                s + r
                if s and {*removesuffix(r, suffix="}")}.issubset(_SH_VAR_CHARS)
                else ""
            )
        else:
            _, s, r = lhs.rpartition("$")
            return s + r if s and {*r}.issubset(_SH_VAR_CHARS) else ""


def _split(sep: str, text: str) -> Iterator[str]:
    acc: MutableSequence[str] = []
    for char in text:
        if char == sep:
            yield "".join(acc)
            acc.clear()
        acc.append(char)
    if acc:
        yield "".join(acc)


def separate(seps: AbstractSet[str], line: str) -> Iterator[str]:
    if not seps:
        yield line
    else:
        sep = next(iter(seps))
        for l in _split(sep, line):
            yield from separate(seps - {sep}, l)


def segs(seps: AbstractSet[str], line: str) -> Iterator[str]:
    segments = tuple(separate(seps, line=line))
    for idx in range(1, len(segments)):
        lhs, rhs = segments[idx - 1 : idx], segments[idx:]
        l = p_lhs(os, lhs="".join(lhs))
        yield "".join(chain((l,), rhs))


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
    for segment in segs(seps, line=line):
        s1 = segment
        s2 = expanduser(s1)
        s3 = expandvars(s2)

        for idx, s0 in enumerate((s1, s2, s3)):
            if idx and s0 == s1:
                pass
            else:
                p = Path(s0)
                entire = p if p.is_absolute() else base / p
                with suppress(FileNotFoundError, NotADirectoryError, PermissionError):
                    if entire.is_dir():
                        for path in scandir(entire):
                            term = sep if path.is_dir() else ""
                            line = _join(segment, path.name) + term
                            yield PurePath(path.path), line
                        return

                    else:
                        lft, go, rhs = s0.rpartition(sep)
                        if go:
                            lp, sp, _ = segment.rpartition(sep)
                            lseg = lp + sp

                            lhs = lft + go
                            p = Path(lhs)
                            left = p if p.is_absolute() else base / p
                            if left.is_dir():
                                for path in scandir(left):
                                    ratio = quick_ratio(
                                        lower(rhs),
                                        lower(path.name),
                                        look_ahead=look_ahead,
                                    )
                                    if (
                                        ratio >= fuzzy_cutoff
                                        and len(path.name) + look_ahead >= len(rhs)
                                        and not rhs.startswith(path.name)
                                    ):
                                        term = sep if path.is_dir() else ""
                                        line = _join(lseg, path.name) + term
                                        yield PurePath(path.path), line
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

        def cont() -> Iterator[Path]:
            if PathResolution.cwd in self._options.resolution:
                yield Path(context.cwd)

            if PathResolution.file in self._options.resolution:
                yield Path(context.filename).parent

        base_paths = {*cont()}

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
                        weight_adjust=self._options.weight_adjust,
                        label=edit.new_text,
                        sort_by=sort_by(
                            self._supervisor.options.unifying_chars, new_text=new_text
                        ),
                        primary_edit=edit,
                        extern=(Extern.path, normcase(path)),
                        icon_match="Folder" if new_text.endswith(sep) else "File",
                    )
                    yield completion
