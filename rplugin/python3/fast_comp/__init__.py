from asyncio import AbstractEventLoop, run_coroutine_threadsafe
from concurrent.futures import ThreadPoolExecutor
from traceback import format_exc
from typing import Any, Awaitable, Sequence

from pynvim import Nvim, command, function, plugin

from .completion import merge
from .da import anext
from .nvim import autocmd, call, complete
from .settings import initial, load_factories


@plugin
class Main:
    def __init__(self, nvim: Nvim):
        self.nvim = nvim
        self.chan = ThreadPoolExecutor(max_workers=1)

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

        if self._initialized:
            return
        else:
            self._initialized = True
            self._submit(setup())

    async def populate_pum(self) -> None:
        results = await anext(self.gen)
        await call(self.nvim, complete(self.nvim, comp=results))

    @function("_FCtextchangedi")
    def text_changed_i(self, args: Sequence[Any]) -> None:
        self._submit(self.populate_pum())

    @function("_FCtextchangedp")
    def text_changed_p(self, args: Sequence[Any]) -> None:
        # self._submit(self.comp())
        pass
