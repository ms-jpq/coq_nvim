from asyncio import AbstractEventLoop, Queue, run_coroutine_threadsafe
from multiprocessing import ThreadPoolExecutor
from traceback import format_exc
from typing import Awaitable

from pynvim import Nvim, autocmd, plugin


@plugin
class Main:
    def __init__(self, nvim: Nvim):
        self.nvim = nvim
        self.chan = ThreadPoolExecutor(max_workers=1)
        self.ch: Queue = Queue()

    def _submit(self, co: Awaitable[None], wait: bool = True) -> None:
        loop: AbstractEventLoop = self.nvim.loop

        def run(nvim: Nvim) -> None:
            fut = run_coroutine_threadsafe(co, loop)
            if wait:
                try:
                    fut.result()
                except Exception as e:
                    stack = format_exc()
                    nvim.async_call(nvim.err_write, f"{stack}{e}\n")

        self.chan.submit(run, self.nvim)

    @autocmd("TextChangedI")
    def comp1(self) -> None:
        pass

    @autocmd("TextChangedP")
    def comp2(self) -> None:
        pass
