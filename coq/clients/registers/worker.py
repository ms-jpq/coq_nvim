from asyncio import create_task
from typing import AbstractSet, AsyncIterator, Mapping, MutableSet

from pynvim_pp.atomic import Atomic
from pynvim_pp.logging import suppress_and_log
from std2.string import removesuffix

from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import RegistersClient
from ...shared.types import Completion, Context, Doc, Edit, SnippetEdit, SnippetGrammar
from .db.database import RDB


async def _registers(names: AbstractSet[str]) -> Mapping[str, str]:
    atomic = Atomic()
    for name in names:
        atomic.call_function("getreg", (name,))
    contents = await atomic.commit(str)

    return {name: txt for name, txt in zip(names, contents)}


class Worker(BaseWorker[RegistersClient, RDB]):
    def __init__(
        self, supervisor: Supervisor, options: RegistersClient, misc: RDB
    ) -> None:
        self._yanked: MutableSet[str] = {*options.words, *options.lines}
        super().__init__(supervisor, options=options, misc=misc)
        create_task(self._poll())

    async def _poll(self) -> None:
        while True:
            with suppress_and_log():
                yanked = {*self._yanked}
                self._yanked.clear()
                registers = await _registers(yanked)
                await self._misc.periodical(
                    wordreg={
                        name: text
                        for name, text in registers.items()
                        if name in self._options.words
                    },
                    linereg={
                        name: text
                        for name, text in registers.items()
                        if name in self._options.lines
                    },
                )

            async with self._supervisor.idling:
                await self._supervisor.idling.wait()

    def post_yank(self, regname: str, regsize: int) -> None:
        if not regname and regsize >= self._options.max_yank_size:
            return

        name = regname or "0"
        if name in {*self._options.words, *self._options.lines}:
            self._yanked.add(name)

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        async with self._work_lock:
            before = removesuffix(context.line_before, suffix=context.syms_before)
            linewise = not before or before.isspace()
            words = await self._misc.select(
                linewise,
                match_syms=self._options.match_syms,
                opts=self._supervisor.match,
                word=context.words,
                sym=context.syms,
                limitless=context.manual,
            )
            for word in words:
                edit = (
                    SnippetEdit(new_text=word.text, grammar=SnippetGrammar.lit)
                    if word.linewise
                    else Edit(new_text=word.text)
                )
                docline = f"{self._options.short_name}{self._options.register_scope}{word.regname}"
                doc = Doc(
                    text=docline,
                    syntax="",
                )
                cmp = Completion(
                    source=self._options.short_name,
                    always_on_top=self._options.always_on_top,
                    weight_adjust=self._options.weight_adjust,
                    label=edit.new_text,
                    sort_by=word.match,
                    primary_edit=edit,
                    adjust_indent=False,
                    doc=doc,
                    icon_match="Text",
                )
                yield cmp
