from asyncio import (
    AbstractEventLoop,
    Queue,
    create_task,
    gather,
    run_coroutine_threadsafe,
)
from typing import Any, Awaitable, Sequence

from pynvim import Nvim, command, function, plugin

from .server.completion import GenOptions, merge
from .server.logging import log, setup
from .server.nvim import autocmd, complete
from .server.patch import apply_patch
from .server.scheduler import Signal, schedule
from .server.settings import initial
from .server.snippet import gen_engine
from .server.state import initial as initial_state
from .server.transitions import (
    t_char_inserted,
    t_comp_inserted,
    t_natural_insertable,
    t_text_changed,
)
from .server.types import Notification
from .shared.consts import conf_var_name, conf_var_name_private
from .shared.executor import Executor
from .shared.nvim import print, run_forever


@plugin
class Main:
    def __init__(self, nvim: Nvim) -> None:
        self.nvim = nvim
        self.chan = Executor()
        self.ch: Queue = Queue()
        self.reply_ch: Queue = Queue()
        self.msg_ch: Queue = Queue()

        self._initialized = False
        user_config = nvim.vars.get(conf_var_name, {})
        client_config = nvim.vars.get(conf_var_name_private, {})
        settings = initial(configs=(client_config, user_config))
        self.settings = settings
        self.state = initial_state(settings)
        setup(nvim, settings.logging_level)
        self._init = create_task(self.initialize())
        run_forever(nvim, thing=self.ooda)

    def _submit(self, co: Awaitable[None]) -> None:
        loop: AbstractEventLoop = self.nvim.loop

        def run(nvim: Nvim) -> None:
            fut = run_coroutine_threadsafe(co, loop)
            try:
                fut.result()
            except Exception as e:
                log.exception("%s", e)

        self.chan.run_sync(run, self.nvim)

    async def initialize(self) -> None:
        await autocmd(self.nvim, events=("InsertEnter",), fn="_NARCinsert_enter")

        await autocmd(self.nvim, events=("InsertCharPre",), fn="_NARCpreinsert_char")

        await autocmd(
            self.nvim, events=("TextChangedI",), fn="_NARCtextchangedi",
        )

        await autocmd(
            self.nvim, events=("TextChangedP",), fn="_NARCtextchangedp",
        )

        await autocmd(
            self.nvim,
            events=("CompleteDonePre",),
            fn="_NARCpost_pum",
            arg_eval=("v:completed_item",),
        )

    async def ooda(self) -> None:
        nvim, msg_ch, settings = self.nvim, self.msg_ch, self.settings
        gen_c, chans_1 = await merge(nvim, settings=settings)
        engine, chans_2, engine_available = await gen_engine(nvim, settings=settings)

        async def l0() -> None:
            chans = {**chans_2, **chans_1}
            while True:
                notif: Notification = await msg_ch.get()
                ch = chans.get(notif.source)
                if ch:
                    await ch.put(notif.body)

        async def l1() -> None:
            async for pos, comp in schedule(chan=self.ch, gen=gen_c):
                col = pos.col + 1
                await complete(self.nvim, col=col, comp=comp)

        async def l2() -> None:
            while True:
                comp = await self.reply_ch.get()
                applied = await apply_patch(
                    self.nvim,
                    engine=engine,
                    engine_available=engine_available,
                    comp=comp,
                )
                if applied:
                    self.state = t_comp_inserted(self.state)

        await gather(l0(), l1(), l2())

    def next_comp(self, options: GenOptions) -> None:
        async def cont() -> None:
            await self.ch.put(Signal(args=(options,)))

        self._submit(cont())

    @command("NARCstart", nargs="*")
    def start(self, args: Sequence[str]) -> None:
        async def cont() -> None:
            await self._init
            await print(self.nvim, "NARC ⭐️")

        self._submit(cont())

    @function("_NARCnotify")
    def notify(self, args: Sequence[Any]) -> None:
        async def cont() -> None:
            source, *body = args
            notif = Notification(source=source, body=body)
            await self.msg_ch.put(notif)

        self._submit(cont())

    @function("NARComnifunc", sync=True)
    def omnifunc(self, args: Sequence[Any]) -> int:
        find_start, *_ = args
        if find_start == 1:
            return -1
        else:
            self.next_comp(GenOptions(force=True))
            return -2

    @function("_NARCinsert_enter")
    def insert_enter(self, args: Sequence[Any]) -> None:
        self.next_comp(GenOptions())

    @function("_NARCpreinsert_char")
    def char_inserted(self, args: Sequence[Any]) -> None:
        self.state = t_char_inserted(self.state)

    @function("_NARCtextchangedi")
    def text_changed_i(self, args: Sequence[Any]) -> None:
        try:
            if t_natural_insertable(self.state):
                self.next_comp(GenOptions())
        finally:
            self.state = t_text_changed(self.state)

    @function("_NARCtextchangedp")
    def text_changed_p(self, args: Sequence[Any]) -> None:
        try:
            if t_natural_insertable(self.state):
                self.next_comp(GenOptions())
        finally:
            self.state = t_text_changed(self.state)

    @function("_NARCpost_pum")
    def post_pum(self, args: Sequence[Any]) -> None:
        comp, *_ = args

        async def cont() -> None:
            await self.reply_ch.put(comp)

        self._submit(cont())
