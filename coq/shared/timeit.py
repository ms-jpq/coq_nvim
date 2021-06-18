from contextlib import contextmanager
from typing import Any, Iterator

from pynvim_pp.logging import log
from std2.timeit import timeit as _timeit


@contextmanager
def timeit(threshold: float, name: str, *args: Any) -> Iterator[None]:
    with _timeit() as t:
        yield None
    delta = t()
    if delta > threshold:
        msg = f"TIME -- {name.ljust(9)} :: {format(delta, '0.3f')} {' '.join(args)}"
        log.debug("%s", msg)

