from contextlib import contextmanager
from typing import Any, Iterator, MutableMapping, Tuple

from pynvim_pp.logging import log
from std2.locale import si_prefixed_smol
from std2.timeit import timeit as _timeit

from ..consts import DEBUG

_RECORDS: MutableMapping[str, Tuple[int, float]] = {}


@contextmanager
def timeit(name: str, *args: Any) -> Iterator[None]:
    if DEBUG:
        with _timeit() as t:
            yield None
        delta = t()

        times, cum = _RECORDS.get(name, (0, 0))
        tt, c = times + 1, cum + delta
        _RECORDS[name] = tt, c

        label = name.ljust(40)
        time = f"{si_prefixed_smol(delta, precision=0)}s".ljust(8)
        ttime = f"{si_prefixed_smol(c / tt, precision=0)}s".ljust(8)
        msg = f"TIME -- {label} :: {time} @ {ttime} {' '.join(map(str, args))}"
        log.info("%s", msg)
    else:
        yield None

