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


def _parse(maybe_path: str) -> Iterator[Tuple[str, Path]]:
    entire = Path(maybe_path)
    lhs, go, rhs = maybe_path.rpartition(sep)
    left_side = Path(lhs)

    if entire.is_dir():
        prefix = str(entire)
        try:
            for path in entire.iterdir():
                yield prefix, path
        except PermissionError:
            pass
    elif go and left_side.is_dir():
        prefix = str(left_side)
        try:
            for path in left_side.iterdir():
                if path.name.startswith(rhs):
                    yield prefix, path
        except PermissionError:
            pass
    else:
        yield from _parse(lhs)
        pass


class Worker(BaseWorker[None]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        context.line_before

        def cont() -> Iterator[Completion]:
            lhs, go, rhs = context.line_before.rpartition(sep)
            if go:
                left = _p_lhs(lhs)
                maybe_path = left + sep + rhs
                for prefix, path in _parse(maybe_path):
                    new_text = str(path)
                    edit = ContextualEdit(
                        old_prefix=prefix, new_text=new_text, new_prefix=new_text
                    )
                    completion = Completion(primary_edit=edit)
                    yield completion

        yield tuple(cont())

