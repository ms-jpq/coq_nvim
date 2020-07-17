from asyncio import AbstractEventLoop, Queue, run_coroutine_threadsafe
from concurrent.futures import ThreadPoolExecutor
from traceback import format_exc
from typing import Any, Awaitable, Sequence

from pynvim import Nvim, command, function, plugin

from .completion import merge
from .nvim import autocmd, complete, print
from .scheduler import schedule, sig
from .settings import initial, load_factories


@plugin
class Main:
    def __init__(self, nvim: Nvim):
        self.nvim = nvim
        self.chan = ThreadPoolExecutor(max_workers=1)
        self.ch: Queue = Queue()

        self._initialized = False
        self._charinserted = False

    def _submit(self, co: Awaitable[None], wait: bool = True) -> None:
        loop: AbstractEventLoop = self.nvim.loop

        def run(nvim: Nvim) -> None:
            fut = run_coroutine_threadsafe(co, loop)
            if wait:
                try:
                    fut.result()
                except Exception as e:
                    stack = format_exc()
                    nvim.async_call(nvim.err_write, f"{stack}{e}")

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

            await autocmd(self.nvim, events=("InsertCharPre",), fn="_FCpreinsert_char")

        async def forever() -> None:
            while True:
                try:
                    await self._ooda()
                except Exception as e:
                    stack = format_exc()
                    await print(self.nvim, f"{stack}{e}", error=True)

        if self._initialized:
            return
        else:
            self._initialized = True
            self._submit(setup())
            self._submit(forever(), wait=False)

        self._submit(print(self.nvim, "Fast Comp 🍎"))

    async def _ooda(self) -> None:
        settings = initial(user_config={})
        factories = load_factories(settings=settings)
        gen = await merge(self.nvim, factories=factories)

        async for comp in schedule(chan=self.ch, gen=gen):
            await complete(self.nvim, comp=comp)

    def next_comp(self) -> None:
        async def cont() -> None:
            await self.ch.put(sig)

        self._submit(cont())

    @function("_FCpreinsert_char")
    def char_inserted(self, args: Sequence[Any]) -> None:
        self._charinserted = True

    @function("_FCtextchangedi")
    def text_changed_i(self, args: Sequence[Any]) -> None:
        try:
            self.next_comp()
        finally:
            self._charinserted = False

    @function("_FCtextchangedp")
    def text_changed_p(self, args: Sequence[Any]) -> None:
        try:
            if self._charinserted:
                self.next_comp()
        finally:
            self.char_inserted = False
