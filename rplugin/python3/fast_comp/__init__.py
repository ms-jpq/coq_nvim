from asyncio import AbstractEventLoop, Queue, run_coroutine_threadsafe
from concurrent.futures import ThreadPoolExecutor
from traceback import format_exc
from typing import Any, Awaitable, Sequence

from pynvim import Nvim, command, function, plugin

from .completion import merge
from .nvim import autocmd, complete, print
from .scheduler import schedule
from .settings import initial, load_factories
from .state import initial as init_state
from .transitions import t_on_char, t_on_insert


@plugin
class Main:
    def __init__(self, nvim: Nvim):
        self.nvim = nvim
        self.chan = ThreadPoolExecutor(max_workers=1)
        self.ch: Queue = Queue()

        self.state = init_state()
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

    def _run(self, fn: Any, *args: Any, **kwargs: Any) -> None:
        async def run() -> None:
            draw, new_state = await fn(self.nvim, state=self.state, *args, **kwargs)
            self.state = new_state
            if draw:
                await self.ch.put(None)

        self._submit(run())

    @command("FCstart")
    def initialize(self) -> None:
        async def setup() -> None:
            await autocmd(
                self.nvim,
                events=("TextChangedI", "TextChangedP",),
                fn="_FCtextchanged",
            )

            await autocmd(self.nvim, events=("InsertCharPre",), fn="_FCpreinsert_char")

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

    @function("_FCtextchanged")
    def text_changed_i(self, args: Sequence[Any]) -> None:
        self._run(t_on_insert)

    @function("_FCpreinsert_char")
    def text_changed_p(self, args: Sequence[Any]) -> None:
        self._run(t_on_char)
