from asyncio import create_task, gather, wrap_future
from concurrent.futures import Future, InvalidStateError
from contextlib import suppress
from functools import lru_cache
from queue import SimpleQueue
from shutil import which
from subprocess import CalledProcessError
from threading import Thread
from typing import Any, Awaitable, Callable, Sequence, TypeVar, cast

from pynvim_pp.logging import suppress_and_log
from std2.asyncio.subprocess import call

_T = TypeVar("_T")


class SingleThreadExecutor:
    def __init__(self) -> None:
        self._q: SimpleQueue = SimpleQueue()

        def cont() -> None:
            while True:
                with suppress_and_log():
                    f = self._q.get()
                    f()

        self._th = Thread(daemon=True, target=cont)
        self._th.start()

    def _submit(self, f: Callable[..., Any], *args: Any, **kwargs: Any) -> Future:
        fut: Future = Future()

        def cont() -> None:
            try:
                ret = f(*args, **kwargs)
            except BaseException as e:
                with suppress(InvalidStateError):
                    fut.set_exception(e)
            else:
                with suppress(InvalidStateError):
                    fut.set_result(ret)

        self._q.put(cont)
        return fut

    def ssubmit(self, f: Callable[..., _T], *args: Any, **kwargs: Any) -> _T:
        fut = self._submit(f, *args, **kwargs)
        result = cast(_T, fut.result())
        return result

    def submit(self, f: Callable[..., _T], *args: Any, **kwargs: Any) -> Awaitable[_T]:
        return wrap_future(self._submit(f, *args, **kwargs))


@lru_cache(maxsize=None)
def very_nice() -> Awaitable[Sequence[str]]:
    async def cont() -> Sequence[str]:
        if tp := which("taskpolicy"):
            run: Sequence[str] = (tp, "-c", "utility", "--")
            try:
                await call(*run, "true")
            except (OSError, CalledProcessError):
                return ()
            else:
                return run
        elif (sd := which("systemd-notify")) and (sr := which("systemd-run")):
            run = (
                sr,
                "--user",
                "--scope",
                "--nice",
                "19",
                "--property",
                "CPUWeight=69",
                "--",
            )
            try:
                await gather(call(sd, "--booted"), call(*run, "true"))
            except (OSError, CalledProcessError):
                return ()
            else:
                return run
        else:
            return ()

    return create_task(cont())
