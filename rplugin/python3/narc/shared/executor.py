from asyncio import Future as AFuture
from concurrent.futures import Future
from queue import SimpleQueue
from threading import Thread
from typing import Any, Callable, TypeVar

T = TypeVar("T")


class Executor:
    def __init__(self) -> None:
        self.__th = Thread(target=self.__ooda, daemon=True)
        self.__chan: SimpleQueue = SimpleQueue()
        self.__th.start()

    def __ooda(self) -> None:
        while True:
            f = self.__chan.get()
            f()

    async def run(self, f: Callable[..., T], *args: Any, **kwargs: Any) -> T:
        fut: AFuture = AFuture()

        def cont() -> None:
            try:
                ret = f(*args, **kwargs)
                fut.set_result(ret)
            except BaseException as e:
                fut.set_exception(e)

        self.__chan.put_nowait(cont)
        await fut
        return fut.result()

    def run_sync(self, f: Callable[..., T], *args: Any, **kwargs: Any) -> Future:
        fut: Future = Future()

        def cont() -> None:
            try:
                ret = f(*args, **kwargs)
                fut.set_result(ret)
            except BaseException as e:
                fut.set_exception(e)

        self.__chan.put_nowait(cont)
        return fut
