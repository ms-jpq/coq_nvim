from asyncio import AbstractEventLoop, Queue, run_coroutine_threadsafe
from concurrent.futures import ThreadPoolExecutor
from traceback import format_exc
from typing import Any, Awaitable, Sequence, cast

from pynvim import Nvim, command, function, plugin

from .completion import merge
from .nvim import autocmd, complete, print
from .scheduler import schedule
from .settings import initial, load_factories
from .state import initial as init_state
from .transitions import (
    render,
    t_char_inserted,
    t_comp_done,
    t_text_changed_i,
    t_text_changed_p,
)


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
            self.state = await fn(self.nvim, state=self.state, *args, **kwargs)
            if render(self.state):
                await self.ch.put(None)

        self._submit(run())

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

            await autocmd(
                self.nvim,
                events=("CompleteDonePre",),
                fn="_FCcomp_done",
                arg_eval=("v:completed_item",),
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

        self._submit(print(self.nvim, "Fast Comp 🍎"))

    async def _ooda(self) -> None:
        settings = initial(user_config={})
        factories = load_factories(settings=settings)
        gen = merge(self.nvim, factories=factories)

        async for comp in schedule(chan=self.ch, gen=gen):
            col = cast(int, self.state.col)
            c = col + 1
            await complete(self.nvim, col=c, comp=comp)

    @function("_FCpreinsert_char")
    def char_inserted(self, args: Sequence[Any]) -> None:
        self._run(t_char_inserted)

    @function("_FCtextchangedi")
    def text_changed_i(self, args: Sequence[Any]) -> None:
        self._run(t_text_changed_i)

    @function("_FCtextchangedp")
    def text_changed_p(self, args: Sequence[Any]) -> None:
        self._run(t_text_changed_p)

    @function("_FCcomp_done")
    def comp_done(self, args: Sequence[Any]) -> None:
        select, *_ = args
        self._run(t_comp_done, select=select)
