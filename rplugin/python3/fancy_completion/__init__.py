from asyncio import (
    AbstractEventLoop,
    Queue,
    create_task,
    gather,
    run_coroutine_threadsafe,
)
from concurrent.futures import ThreadPoolExecutor
from locale import strxfrm
from traceback import format_exc
from typing import Any, Awaitable, Sequence

from pynvim import Nvim, command, function, plugin

from .server.completion import GenOptions, merge
from .server.nvim import autocmd, complete
from .server.patch import apply_patch
from .server.scheduler import Signal, schedule
from .server.settings import initial, load_factories
from .server.state import initial as initial_state
from .server.transitions import (
    t_char_inserted,
    t_comp_inserted,
    t_natural_insertable,
    t_set_sources,
    t_text_changed,
    t_toggle_sources,
)
from .server.types import Notification
from .shared.nvim import print, run_forever


@plugin
class Main:
    def __init__(self, nvim: Nvim):
        self.nvim = nvim
        self.chan = ThreadPoolExecutor(max_workers=1)
        self.ch: Queue = Queue()
        self.msg_ch: Queue = Queue()

        self._initialized = False
        user_config = nvim.vars.get("fancy_completion_settings", {})
        client_config = nvim.vars.get("fancy_completion_settings_private", {})
        settings = initial(configs=(client_config, user_config))
        self.settings = settings
        self.state = initial_state(settings)

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

        async def ooda() -> None:
            settings = self.settings
            factories = load_factories(settings=settings)
            gen, listen = await merge(
                self.nvim, chan=self.msg_ch, factories=factories, settings=settings
            )

            async def l1() -> None:
                async for pos, comp in schedule(chan=self.ch, gen=gen):
                    col = pos.col + 1
                    await complete(self.nvim, col=col, comp=comp)
                    self.state = t_comp_inserted(self.state)

            await gather(listen(), l1())

        if self._initialized:
            pass
        else:
            self._initialized = True
            self._submit(setup())
            run_forever(self.nvim, ooda)

        self._submit(print(self.nvim, "Fancy Completion ⭐️"))

    def next_comp(self, options: GenOptions) -> None:
        async def cont() -> None:
            await self.ch.put(Signal(args=(options,)))

        self._submit(cont())

    @function("_FCnotify")
    def notify(self, args: Sequence[Any]) -> None:
        async def cont() -> None:
            source, *body = args
            notif = Notification(source=source, body=body)
            await self.msg_ch.put(notif)

        self._submit(cont())

    @function("FCmanual", sync=True)
    def manual(self, args: Sequence[Any]) -> None:
        self.next_comp(GenOptions(force=False, sources=self.state.sources))

    @function("FComnifunc", sync=True)
    def omnifunc(self, args: Sequence[Any]) -> int:
        find_start, *_ = args
        if find_start == 1:
            return -1
        else:
            self.next_comp(GenOptions(force=False, sources=self.state.sources))
            return -2

    @function("_FCpreinsert_char")
    def char_inserted(self, args: Sequence[Any]) -> None:
        self.state = t_char_inserted(self.state)

    @function("_FCtextchangedi")
    def text_changed_i(self, args: Sequence[Any]) -> None:
        try:
            if t_natural_insertable(self.state):
                self.next_comp(GenOptions(force=False, sources=self.state.sources))
        finally:
            self.state = t_text_changed(self.state)

    @function("_FCtextchangedp")
    def text_changed_p(self, args: Sequence[Any]) -> None:
        try:
            if t_natural_insertable(self.state):
                self.next_comp(GenOptions(force=False, sources=self.state.sources))
        finally:
            self.state = t_text_changed(self.state)

    @function("_FCpost_pum")
    def post_pum(self, args: Sequence[Any]) -> None:
        item, *_ = args
        apply_patch(self.nvim, comp=item)

    @function("FCset_sources")
    def set_sources(self, args: Sequence[Any]) -> None:
        candidates, *_ = args
        self.state = t_set_sources(
            self.state, settings=self.settings, candidates=candidates
        )

    @function("FCtoggle_sources")
    def toggle_sources(self, args: Sequence[Any]) -> None:
        candidates, *_ = args
        self.state = t_toggle_sources(
            self.state, settings=self.settings, candidates=candidates
        )

    def _print_sources(self) -> None:
        sources = sorted(self.state.sources, key=strxfrm)
        s_repr = ", ".join(sources)
        msg = f"New sources - {s_repr}"
        self._submit(print(self.nvim, msg))

    @command("FCSetSources", nargs="*")
    def c_set_sources(self, args: Sequence[Any]) -> None:
        self.set_sources((args,))
        self._print_sources()

    @command("FCToggleSources", nargs="*")
    def c_toggle_sources(self, args: Sequence[Any]) -> None:
        self.toggle_sources((args,))
        self._print_sources()
