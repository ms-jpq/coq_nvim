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
from .nvim import autocmd, call, complete, print
from .patch import apply_patch
from .scheduler import Signal, schedule
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

            await autocmd(
                self.nvim,
                events=("CompleteDonePre",),
                fn="_FCpost_pum",
                arg_eval=("v:completed_item",),
            )

        async def gen_user_config() -> Any:
            def cont() -> Any:
                user_config = self.nvim.vars.get("fancy_completion_settings", {})
                return user_config

            return await call(self.nvim, cont)

        async def ooda() -> None:
            try:
                user_config = await gen_user_config()
                settings = initial(user_config=user_config)
                factories = load_factories(settings=settings)
                gen, listen = await merge(
                    self.nvim, chan=self.msg_ch, factories=factories, settings=settings
                )

                async def l1() -> None:
                    async for pos, comp in schedule(chan=self.ch, gen=gen):
                        col = pos.col + 1
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

        self._submit(print(self.nvim, "Fancy Completion ⭐️"))

    def next_comp(self, force: bool) -> None:
        async def cont() -> None:
            await self.ch.put(Signal(args=(force,)))

        self._submit(cont())

    @function("FCmanual", sync=True)
    def manual(self, args: Sequence[Any]) -> None:
        self.next_comp(force=True)

    @function("FComnifunc", sync=True)
    def omnifunc(self, args: Sequence[Any]) -> int:
        find_start, *_ = args
        if find_start == 1:
            return -1
        else:
            self.next_comp(force=True)
            return -2

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
            self.next_comp(force=False)
        finally:
            self.state = forward(self.state, char_inserted=False)

    @function("_FCtextchangedp")
    def text_changed_p(self, args: Sequence[Any]) -> None:
        try:
            if self.state.char_inserted:
                self.next_comp(force=False)
        finally:
            self.state = forward(self.state, char_inserted=False)

    @function("_FCpost_pum")
    def post_pum(self, args: Sequence[Any]) -> None:
        item, *_ = args
        apply_patch(self.nvim, comp=item)
