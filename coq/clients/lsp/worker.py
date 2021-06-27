from concurrent.futures import CancelledError, Future, InvalidStateError
from contextlib import suppress
from os import linesep
from pathlib import Path
from threading import Lock
from typing import Any, Iterator, Optional, Sequence, Tuple, cast
from uuid import UUID, uuid4

from pynvim_pp.lib import threadsafe_call
from pynvim_pp.logging import log
from std2.pickle import DecodeError, decode

from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import LSPClient
from ...shared.types import (
    UTF16,
    Completion,
    Context,
    Doc,
    Edit,
    RangeEdit,
    SnippetEdit,
    WTF8Pos,
)
from .types import CompletionItem, CompletionList, MarkupContent, Resp, TextEdit

_LUA = (Path(__file__).resolve().parent / "request.lua").read_text("UTF-8")


def _range_edit(edit: TextEdit) -> RangeEdit:
    begin = edit.range.start.line, edit.range.end.character
    end = edit.range.end.line, edit.range.end.character
    return RangeEdit(new_text=edit.newText, begin=begin, end=end)


def _primary(client: LSPClient, item: CompletionItem) -> Edit:
    fmt = None if item.insertTextFormat is None else str(item.insertTextFormat)

    if client.InsertTextFormat.get(cast(Any, fmt)) == "Snippet":
        return SnippetEdit(grammar="lsp", new_text=item.insertText or item.label)
    elif isinstance(item.textEdit, TextEdit):
        return _range_edit(item.textEdit)
    else:
        return Edit(new_text=item.insertText or item.label)


def _doc(item: CompletionItem) -> Optional[Doc]:
    if isinstance(item.documentation, MarkupContent):
        return Doc(text=item.documentation.value, filetype=item.documentation.kind)
    elif isinstance(item.documentation, str):
        return Doc(text=item.documentation, filetype="")
    elif item.detail:
        return Doc(text=item.detail, filetype="")
    else:
        return None


def _parse_item(client: LSPClient, item: CompletionItem) -> Completion:
    cmp = Completion(
        source=client.short_name,
        tie_breaker=client.tie_breaker,
        label=item.label,
        primary_edit=_primary(client, item=item),
        secondary_edits=tuple(map(_range_edit, item.additionalTextEdits or ())),
        sort_by=item.filterText or "",
        kind=client.CompletionItemKind.get(
            cast(Any, None if item.kind is None else str(item.kind)), ""
        ),
        doc=_doc(item),
    )
    return cmp


def _parse(client: LSPClient, reply: Any) -> Tuple[bool, Sequence[Completion]]:
    try:
        resp: Resp = decode(Resp, reply, strict=False)
    except DecodeError as e:
        log.exception("%s", f"{reply}{linesep}{e}")
        return False, ()
    else:
        if isinstance(resp, CompletionList):
            # TODO -- resp.isIncomplete always True???
            return False, tuple(_parse_item(client, item=item) for item in resp.items)
        elif isinstance(resp, Sequence):
            return False, tuple(_parse_item(client, item=item) for item in resp)
        else:
            return False, ()


class Worker(BaseWorker[LSPClient, None]):
    def __init__(self, supervisor: Supervisor, options: LSPClient, misc: None) -> None:
        self._lock = Lock()
        self._cur: Tuple[UUID, Future] = uuid4(), Future()
        supervisor.nvim.api.exec_lua(_LUA, ())
        super().__init__(supervisor, options=options, misc=misc)

    def _req(self, session: UUID, pos: WTF8Pos) -> Any:
        with self._lock:
            _, fut = self._cur
            fut.cancel()
            self._cur = token, fut = uuid4(), Future()

        def cont() -> None:
            args = (str(token), str(session), pos)
            self._supervisor.nvim.api.exec_lua("COQlsp_req(...)", args)

        threadsafe_call(self._supervisor.nvim, cont)

        try:
            ret = fut.result()
        except CancelledError:
            ret = None

        return ret

    def notify(self, token: UUID, msg: Sequence[Any]) -> None:
        with self._lock:
            c_token, fut = self._cur
            if token == c_token:
                reply, *_ = msg
                with suppress(InvalidStateError):
                    fut.set_result(reply)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        session = uuid4()
        row, c = context.position
        col = len(context.line_before[:c].encode(UTF16)) // 2

        go = True
        while go:
            reply = self._req(session, pos=(row, col))
            go, comps = _parse(self._options, reply=reply)
            yield comps

