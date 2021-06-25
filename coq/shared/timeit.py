from contextlib import contextmanager
from typing import Any, Iterator

from pynvim_pp.logging import log
from std2.locale import si_prefixed_smol
from std2.timeit import timeit as _timeit


@contextmanager
def timeit(threshold: float, name: str, *args: Any) -> Iterator[None]:
    with _timeit() as t:
        yield None
    delta = t()
    time = si_prefixed_smol(delta, precision=3)
    if delta > threshold:
        msg = f"TIME -- {name.ljust(9)} :: {time} {' '.join(args)}"
        log.debug("%s", msg)

