from asyncio import AbstractEventLoop, run_coroutine_threadsafe
from concurrent.futures import ThreadPoolExecutor
from traceback import format_exc
from typing import Awaitable

from pynvim import Nvim, autocmd, plugin

from .completion import merge
from .da import anext
from .nvim import call, complete
from .settings import initial, load_factories


@plugin
class Main:
    def __init__(self, nvim: Nvim):
        self.nvim = nvim
        self.chan = ThreadPoolExecutor(max_workers=1)

        self.settings = initial(user_config={})
        factories = load_factories(settings=self.settings)
        self.gen = merge(self.nvim, factories=factories)

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

    async def comp(self) -> None:
        results = await anext(self.gen)
        await call(self.nvim, complete(self.nvim, comp=results))

    @autocmd("TextChangedI")
    def comp1(self) -> None:
        self._submit(self.comp())

    # @autocmd("TextChangedP")
    # def comp2(self) -> None:
    #     self._submit(self.comp())
