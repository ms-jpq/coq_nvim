from asyncio import (
    AbstractEventLoop,
    Queue,
    create_task,
    gather,
    run_coroutine_threadsafe,
)
from concurrent.futures import ThreadPoolExecutor
from traceback import format_exc
from typing import Any, Awaitable, Sequence

from pynvim import Nvim, command, function, plugin

from .completion import merge
from .nvim import autocmd, complete, print
from .scheduler import schedule, sig
from .settings import initial, load_factories
from .state import forward
from .state import initial as initial_state
from .types import Notification


@plugin
class Main:
    def __init__(self, nvim: Nvim):
        self.nvim = nvim
        self.chan = ThreadPoolExecutor(max_workers=1)
        self.ch: Queue = Queue()
        self.msg_ch: Queue = Queue()

        self._initialized = False
        self.state = initial_state()

    def _submit(self, co: Awaitable[None], wait: bool = True) -> None:
        loop: AbstractEventLoop = self.nvim.loop

        def run(nvim: Nvim) -> None:
            fut = run_coroutine_threadsafe(co, loop)
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

        async def ooda() -> None:
            try:
                settings = initial(user_config={})
                factories = load_factories(settings=settings)
                gen, listen = await merge(
                    self.nvim, chan=self.msg_ch, factories=factories
                )

                async def l1() -> None:
                    async for col, comp in schedule(chan=self.ch, gen=gen):
                        await complete(self.nvim, col=col, comp=comp)

                await gather(listen(), l1())

            except Exception as e:
                stack = format_exc()
                await print(self.nvim, f"{stack}{e}", error=True)

        if self._initialized:
            pass
        else:
            self._initialized = True
            self._submit(setup())
            create_task(ooda())

        self._submit(print(self.nvim, "Fast Comp 🍎"))

    def next_comp(self) -> None:
        async def cont() -> None:
            await self.ch.put(sig)

        self._submit(cont())

    @function("_FCnotify")
    def notify(self, args: Sequence[Any]) -> None:
        async def cont() -> None:
            source, *body = args
            notif = Notification(source=source, body=body)
            await self.msg_ch.put(notif)

        self._submit(cont())

    @function("_FCpreinsert_char")
    def char_inserted(self, args: Sequence[Any]) -> None:
        self.state = forward(self.state, char_inserted=True)

    @function("_FCtextchangedi")
    def text_changed_i(self, args: Sequence[Any]) -> None:
        try:
            self.state = forward(self.state, char_inserted=False)
            self.next_comp()
        finally:
            self.state = forward(self.state, char_inserted=False)

    @function("_FCtextchangedp")
    def text_changed_p(self, args: Sequence[Any]) -> None:
        try:
            if self.state.char_inserted:
                self.next_comp()
        finally:
            self.state = forward(self.state, char_inserted=False)
