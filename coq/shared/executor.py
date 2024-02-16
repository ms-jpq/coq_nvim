from asyncio import (
    AbstractEventLoop,
    create_task,
    gather,
    get_running_loop,
    run,
    run_coroutine_threadsafe,
    wrap_future,
)
from concurrent.futures import Future, InvalidStateError
from contextlib import suppress
from functools import lru_cache
from shutil import which
from subprocess import CalledProcessError
from threading import Thread
from typing import Any, Awaitable, Callable, Coroutine, Sequence, TypeVar

from std2.asyncio.subprocess import call

_T = TypeVar("_T")


class AsyncExecutor:
    def __init__(self) -> None:
        f: Future = Future()
        self._fut: Future = Future()

        async def cont() -> None:
            loop = get_running_loop()
            f.set_result(loop)
            main: Coroutine = await wrap_future(self._fut)
            await main

        self._th = Thread(daemon=True, target=lambda: run(cont()))
        self._th.start()
        self._loop: AbstractEventLoop = f.result()

    def run(self, main: Awaitable[None]) -> None:
        self._fut.set_result(main)

    def fsubmit(self, f: Callable[..., _T], *args: Any, **kwargs: Any) -> Future:
        fut: Future = Future()

        def cont() -> None:
            if fut.set_running_or_notify_cancel():
                try:
                    ret = f(*args, **kwargs)
                except BaseException as e:
                    with suppress(InvalidStateError):
                        fut.set_exception(e)
                else:
                    with suppress(InvalidStateError):
                        fut.set_result(ret)

        self._loop.call_soon_threadsafe(cont)
        return fut

    def submit(self, co: Awaitable[_T]) -> Awaitable[_T]:
        f = run_coroutine_threadsafe(co, loop=self._loop)
        return wrap_future(f)


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
