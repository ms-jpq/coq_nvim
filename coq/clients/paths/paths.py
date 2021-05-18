from os.path import sep
from pathlib import Path
from typing import Iterator, Sequence, Tuple

from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context, ContextualEdit


def _parse(segments: Sequence[str]) -> Iterator[Tuple[str, Path]]:
    if segments:
        _, body, tail = segments
        p0 = Path(*body)
        p1 = p0 / tail
        if p1.is_dir():
            prefix = sep.join(segments)
            for path in p1.iterdir():
                yield prefix, path
        elif p0.is_dir():
            prefix = sep.join(body)
            for path in p0.iterdir():
                if path.name.startswith(tail):
                    yield prefix, path
        else:
            yield from _parse(body)


class Worker(BaseWorker[None]):
    def work(self, context: Context) -> Sequence[Completion]:
        context.line_before

        def cont() -> Iterator[Completion]:
            segments = context.line_before.split(sep)
            for prefix, path in _parse(segments):
                new_text = str(path)
                edit = ContextualEdit(
                    new_text=new_text, old_prefix=prefix, new_prefix=new_text
                )
                completion = Completion(position=context.position, primary_edit=edit)
                yield completion

        return tuple(cont())
