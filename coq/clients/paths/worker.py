from os import X_OK, access
from os.path import join, sep
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


def _segments(line: str) -> Iterator[str]:
    segments = line.split(sep)
    if len(segments) > 1:
        *rest, front = reversed(segments)
        lhs = _p_lhs(front)
        segs = (*rest, lhs)
        for idx in range(1, len(segs) + 1):
            yield sep.join(reversed(segs[:idx]))


def parse(line: str) -> Iterator[Tuple[str, str]]:
    segments = reversed(tuple(_segments(line)))
    for segment in segments:
        entire = Path(segment).expanduser()
        if entire.is_dir() and access(entire, mode=X_OK):
            for path in entire.iterdir():
                term = sep if path.is_dir() else ""
                yield segment, join(segment, path.name) + term
            break
        else:
            lft, go, rhs = segment.rpartition(sep)
            assert go
            lhs = lft + go
            left = Path(lhs).expanduser()
            if left.is_dir() and access(left, mode=X_OK):
                for path in left.iterdir():
                    if path.name.startswith(rhs):
                        term = sep if path.is_dir() else ""
                        yield segment, join(lhs, path.name) + term
            break


class Worker(BaseWorker[None]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        def cont() -> Iterator[Completion]:
            line = context.line_before + context.words_after
            for prefix, new_text in parse(line):
                edit = ContextualEdit(
                    old_prefix=prefix, new_text=new_text, new_prefix=new_text
                )
                completion = Completion(primary_edit=edit)
                yield completion

        yield tuple(cont())

