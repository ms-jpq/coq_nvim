from asyncio import AbstractEventLoop, Queue, run_coroutine_threadsafe
from concurrent.futures import ThreadPoolExecutor
from traceback import format_exc
from typing import Any, Awaitable, Sequence

from pynvim import Nvim, command, function, plugin

from .completion import merge
from .nvim import autocmd, call, complete, print
from .scheduler import schedule
from .settings import initial, load_factories


@plugin
class Main:
    def __init__(self, nvim: Nvim):
        self.nvim = nvim
        self.chan = ThreadPoolExecutor(max_workers=1)
        self.ch: Queue = Queue(1)

        self.settings = initial(user_config={})
        factories = load_factories(settings=self.settings)
        self.gen = merge(self.nvim, factories=factories)

        self._initialized = False

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

    @command("FCstart")
    def initialize(self) -> None:
        async def setup() -> None:
            await autocmd(
                self.nvim, events=("TextChangedI",), fn="_FCtextchangedi",
            )

            await autocmd(
                self.nvim, events=("TextChangedP",), fn="_FCtextchangedp",
            )

        async def forever() -> None:
            while True:
                try:
                    await self._ooda()
                except Exception as e:
                    await print(self.nvim, e, error=True)

        if self._initialized:
            return
        else:
            self._initialized = True
            self._submit(setup())

    async def _ooda(self) -> None:
        async for comp in schedule(chan=self.ch, gen=self.gen):
            await call(self.nvim, complete(self.nvim, comp=comp))

    @function("_FCtextchangedi")
    def text_changed_i(self, args: Sequence[Any]) -> None:
        async def put() -> None:
            await self.ch.put(None)

        self._submit(put())

    @function("_FCtextchangedp")
    def text_changed_p(self, args: Sequence[Any]) -> None:
        # self._submit(self.comp())
        pass
