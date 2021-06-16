from contextlib import contextmanager
from typing import Iterator

from std2.timeit import timeit as _timeit


@contextmanager
def timeit(f: str, threshold: float = 0.1) -> Iterator[None]:
    with _timeit() as t:
        yield None
    delta = t()
    if delta > threshold:
        print(f"TIME -- {f} :: {delta}", flush=True)

