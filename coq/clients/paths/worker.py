from os.path import sep
from pathlib import Path
from typing import Iterator, Sequence, Tuple

from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context, ContextualEdit


def _parse(segments: Sequence[str]) -> Iterator[Tuple[str, Path]]:
    if segments:
        *lhs, rhs = segments
        left_side = Path(*lhs)
        entire = left_side / rhs

        if entire.is_dir():
            prefix = str(entire)
            try:
                for path in entire.iterdir():
                    yield prefix, path
            except PermissionError:
                pass
        elif left_side.is_dir():
            prefix = str(left_side)
            try:
                for path in left_side.iterdir():
                    if path.name.startswith(rhs):
                        yield prefix, path
            except PermissionError:
                pass
        else:
            yield from _parse(lhs)


class Worker(BaseWorker[None]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        context.line_before

        def cont() -> Iterator[Completion]:
            segments = context.line_before.split(sep)
            if len(segments) > 1:
                _, *segs = segments

                for prefix, path in _parse(segs):
                    new_text = str(path)
                    edit = ContextualEdit(
                        old_prefix=prefix, new_text=new_text, new_prefix=new_text
                    )
                    completion = Completion(primary_edit=edit)
                    yield completion

        yield tuple(cont())

