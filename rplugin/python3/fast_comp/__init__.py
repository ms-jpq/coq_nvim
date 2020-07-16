from asyncio import AbstractEventLoop, Queue, run_coroutine_threadsafe
from concurrent.futures import ThreadPoolExecutor
from traceback import format_exc
from typing import Any, Awaitable, Optional, Sequence

from pynvim import Nvim, command, function, plugin

from .completion import merge
from .nvim import autocmd, call, complete, print
from .scheduler import schedule
from .settings import initial, load_factories
from .types import State


@plugin
class Main:
    def __init__(self, nvim: Nvim):
        self.nvim = nvim
        self.chan = ThreadPoolExecutor(max_workers=1)
        self.ch: Queue = Queue()

        self.state = State(col=-1)
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
            self._submit(forever(), wait=False)

    async def _ooda(self) -> None:
        settings = initial(user_config={})
        factories = load_factories(settings=settings)
        gen = merge(self.nvim, factories=factories)

        async for comp in schedule(chan=self.ch, gen=gen):
            c = self.state.col + 1
            await complete(self.nvim, col=c, comp=comp)

    @function("_FCtextchangedi")
    def text_changed_i(self, args: Sequence[Any]) -> None:
        nvim = self.nvim

        def update() -> State:
            pum_open = nvim.funcs.pumvisible() != 0
            if pum_open:
                return self.state
            else:
                window = nvim.api.get_current_win()
                _, col = nvim.api.win_get_cursor(window)
                return State(col=col)

        async def put() -> None:
            self.state = await call(nvim, update)
            await self.ch.put(None)

        self._submit(put())

    @function("_FCtextchangedp")
    def text_changed_p(self, args: Sequence[Any]) -> None:
        async def put() -> None:
            await self.ch.put(None)

        self._submit(put())
