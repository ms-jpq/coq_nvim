from concurrent.futures import Future, InvalidStateError
from contextlib import suppress
from queue import SimpleQueue
from threading import Lock, Thread
from typing import Any, Callable, TypeVar

T = TypeVar("T")


class Executor:
    def __init__(self) -> None:
        self._lock, self._q = Lock(), SimpleQueue()
        self._th = Thread(target=self._forever, daemon=True)
        self._started = False

    def _forever(self) -> None:
        while True:
            f = self._q.get()
            f()

    def submit(self, f: Callable[..., T], *args: Any, **kwargs: Any) -> T:
        with self._lock:
            if not self._started:
                self._th.start()
                self._started = True

        fut = Future()

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
        return fut.result()
