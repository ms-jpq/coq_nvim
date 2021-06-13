from os.path import sep
from pathlib import Path
from typing import Iterator, Sequence, Tuple

from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context, ContextualEdit


def _p_lhs(lhs: str) -> str:
    for sym in (".", "..", "~"):
        if lhs.endswith(sym):
            return sym
    else:
        return ""


def _parse(maybe_path: str) -> Iterator[Tuple[str, str]]:
    entire = Path(maybe_path)
    lhs, go, rhs = maybe_path.rpartition(sep)
    left_side = Path(lhs)

    if entire.is_dir():
        try:
            prefix = maybe_path
            for path in entire.iterdir():
                yield prefix, str(path)
        except PermissionError:
            pass
    elif go and left_side.is_dir():
        prefix = lhs + sep + rhs
        try:
            for path in left_side.iterdir():
                if path.name.startswith(rhs):
                    yield prefix, str(path)
        except PermissionError:
            pass
    else:
        lhs, go, rhs = maybe_path.partition(sep)
        if go:
            yield from _parse(rhs)


def parse(line: str) -> Iterator[Tuple[str, str]]:
    lhs, go, rhs = line.rpartition(sep)
    if go:
        left = _p_lhs(lhs)
        maybe_path = left + sep + rhs
        yield from _parse(maybe_path)


class Worker(BaseWorker[None]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        context.line_before

        def cont() -> Iterator[Completion]:
            line = context.line_before + context.words_after
            for prefix, new_text in parse(line):
                edit = ContextualEdit(
                    old_prefix=prefix, new_text=new_text, new_prefix=new_text
                )
                completion = Completion(primary_edit=edit)
                yield completion

        yield tuple(cont())

