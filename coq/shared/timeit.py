from contextlib import contextmanager
from typing import Any, Iterator

from pynvim_pp.logging import log
from std2.locale import si_prefixed_smol
from std2.timeit import timeit as _timeit


@contextmanager
def timeit(name: str, *args: Any) -> Iterator[None]:
    with _timeit() as t:
        yield None
    delta = t()
    time = f"{si_prefixed_smol(delta)}s".ljust(8)
    msg = f"TIME -- {name.ljust(9)} :: {time} {' '.join(args)}"
    log.debug("%s", msg)

