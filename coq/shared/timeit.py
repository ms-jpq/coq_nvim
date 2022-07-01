from contextlib import contextmanager
from time import process_time
from typing import Any, Iterator, MutableMapping, Optional, Tuple

from pynvim_pp.logging import log
from std2.locale import si_prefixed_smol
from std2.timeit import timeit as _timeit

from ..consts import DEBUG

_RECORDS: MutableMapping[str, Tuple[int, float]] = {}


@contextmanager
def timeit(
    name: str, *args: Any, force: bool = False, warn: Optional[float] = None
) -> Iterator[None]:
    if DEBUG or force or warn is not None:
        with _timeit() as t:
            yield None
        delta = t().total_seconds()
        if DEBUG or force or delta >= (warn or 0):
            times, cum = _RECORDS.get(name, (0, 0))
            tt, c = times + 1, cum + delta
            _RECORDS[name] = tt, c

            label = name.ljust(50)
            time = f"{si_prefixed_smol(delta, precision=0)}s".ljust(8)
            ttime = f"{si_prefixed_smol(c / tt, precision=0)}s".ljust(8)
            msg = f"TIME -- {label} :: {time} @ {ttime} {' '.join(map(str, args))}"
            if force:
                log.info("%s", msg)
            else:
                log.debug("%s", msg)
    else:
        yield None


@contextmanager
def cpu_timeit() -> Iterator[None]:
    t1 = process_time()
    with _timeit() as t:
        yield None
    t2 = process_time()
    delta = t().total_seconds()
    cpu = (t2 - t1) / delta
    msg = f"CPU :: {cpu}"
    log.info("%s", msg)
