from concurrent.futures import CancelledError, Future, InvalidStateError
from contextlib import suppress
from pathlib import Path
from threading import Lock
from typing import Any, Iterator, Mapping, MutableMapping, Optional, Sequence, Tuple
from uuid import UUID, uuid4

from pynvim_pp.lib import threadsafe_call
from std2.pickle import DecodeError, decode

from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import LSPClient
from ...shared.types import UTF16, Completion, Context, Edit, RangeEdit, WTF8Pos
from .types import CompletionItem, CompletionList, MarkupContent, Resp, TextEdit

_LUA = (Path(__file__).resolve().parent / "request.lua").read_text("UTF-8")


def _range_edit(edit: TextEdit) -> RangeEdit:
    begin = edit.range.start.line, edit.range.end.character
    end = edit.range.end.line, edit.range.end.character
    return RangeEdit(new_text=edit.newText, begin=begin, end=end)


def _primary(item: CompletionItem) -> Edit:
    if isinstance(item.textEdit, TextEdit):
        return _range_edit(item.textEdit)
    elif item.insertText:
        return Edit(new_text=item.insertText)
    else:
        return Edit(new_text=item.label)


def _doc(item: CompletionItem) -> Tuple[str, str]:
    if isinstance(item.documentation, MarkupContent):
        return item.documentation.value, item.documentation.kind
    elif isinstance(item.documentation, str):
        return item.documentation, ""
    elif item.detail:
        return item.detail, ""
    else:
        return "", ""


def _parse_item(
    src: str, kind_lookup: Mapping[Optional[int], str], item: CompletionItem
) -> Completion:
    primary = _primary(item)
    secondaries = tuple(map(_range_edit, item.additionalTextEdits or ()))
    doc, doc_type = _doc(item)

    cmp = Completion(
        source=src,
        primary_edit=primary,
        secondary_edits=secondaries,
        sort_by=item.filterText or "",
        kind=kind_lookup.get(item.kind, ""),
        label=item.label,
        doc=doc,
        doc_type=doc_type,
    )
    return cmp


def _parse(
    src: str, kind_lookup: Mapping[Optional[int], str], reply: Any
) -> Tuple[bool, Sequence[Completion]]:
    try:
        resp: Resp = decode(Resp, reply, strict=False)
    except DecodeError:
        raise
    else:
        if isinstance(resp, CompletionList):
            return resp.isIncomplete, tuple(
                _parse_item(src, kind_lookup=kind_lookup, item=item)
                for item in resp.items
            )
        elif isinstance(resp, Sequence):
            return False, tuple(
                _parse_item(src, kind_lookup=kind_lookup, item=item) for item in resp
            )
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
            ret = fut.result(timeout=self._supervisor.options.timeout)
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
            go, comps = _parse(
                self._options.short_name,
                kind_lookup=self._options.cmp_item_kind,
                reply=reply,
            )
            yield comps

