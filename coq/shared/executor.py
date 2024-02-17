from asyncio import (
    AbstractEventLoop,
    create_task,
    gather,
    get_running_loop,
    run,
    run_coroutine_threadsafe,
    wrap_future,
)
from concurrent.futures import Future, InvalidStateError, ThreadPoolExecutor
from contextlib import suppress
from functools import lru_cache
from shutil import which
from subprocess import CalledProcessError
from threading import Thread
from typing import Any, Awaitable, Callable, Coroutine, Optional, Sequence, TypeVar

from std2.asyncio.subprocess import call

_T = TypeVar("_T")


class AsyncExecutor:
    def __init__(self, threadpool: Optional[ThreadPoolExecutor]) -> None:
        f: Future = Future()
        self._fut: Future = Future()

        async def cont() -> None:
            loop = get_running_loop()
            if threadpool:
                loop.set_default_executor(threadpool)
            f.set_result(loop)
            main: Coroutine = await wrap_future(self._fut)
            await main

        self._th = Thread(daemon=True, target=lambda: run(cont()))
        self._th.start()
        self.loop: AbstractEventLoop = f.result()

    def run(self, main: Awaitable[Any]) -> None:
        self._fut.set_result(main)

    def fsubmit(self, f: Callable[..., Any], *args: Any, **kwargs: Any) -> Future:
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

        self.loop.call_soon_threadsafe(cont)
        return fut

    def submit(self, co: Awaitable[_T]) -> Awaitable[_T]:
        f = run_coroutine_threadsafe(co, loop=self.loop)
        return wrap_future(f)


@lru_cache(maxsize=None)
def _very_nice() -> Future:

    async def c1() -> Sequence[str]:
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

    f: Future = Future()

    async def c2() -> None:
        try:
            ret = await c1()
        except BaseException as e:
            with suppress(InvalidStateError):
                f.set_exception(e)
        else:
            with suppress(InvalidStateError):
                f.set_result(ret)

    create_task(c2())
    return f


async def very_nice() -> Sequence[str]:
    f: Future = _very_nice()
    return await wrap_future(f)
