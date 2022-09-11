from asyncio import wrap_future
from concurrent.futures import Executor, Future, InvalidStateError
from contextlib import suppress
from queue import SimpleQueue
from typing import Any, Awaitable, Callable, TypeVar, cast

from pynvim_pp.logging import suppress_and_log

_T = TypeVar("_T")


class SingleThreadExecutor:
    def __init__(self, pool: Executor) -> None:
        self._q: SimpleQueue = SimpleQueue()
        pool.submit(self._forever)

    def _forever(self) -> None:
        while True:
            with suppress_and_log():
                f = self._q.get()
                f()

    def _submit(self, f: Callable[..., Any], *args: Any, **kwargs: Any) -> Future:
        fut: Future = Future()

        def cont() -> None:
            try:
                ret = f(*args, **kwargs)
            except Exception as e:
                with suppress(InvalidStateError):
                    fut.set_exception(e)
            else:
                with suppress(InvalidStateError):
                    fut.set_result(ret)

        self._q.put(cont)
        return fut

    def ssubmit(self, f: Callable[..., _T], *args: Any, **kwargs: Any) -> _T:
        fut = self._submit(f, *args, **kwargs)
        return cast(_T, fut.result())

    def submit(self, f: Callable[..., _T], *args: Any, **kwargs: Any) -> Awaitable[_T]:
        return wrap_future(self._submit(f, *args, **kwargs))
