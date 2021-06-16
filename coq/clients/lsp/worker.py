from concurrent.futures import Future, InvalidStateError, TimeoutError
from contextlib import suppress
from json import loads
from pathlib import Path
from threading import Lock
from typing import Any, Iterator, MutableMapping, Sequence, Tuple
from uuid import UUID, uuid4

from pynvim_pp.lib import threadsafe_call
from std2.pickle import DecodeError, decode

from ...consts import ARTIFACTS_DIR
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context, Edit, NvimPos, RangeEdit
from .runtime import LSP
from .types import CompletionItem, CompletionList, MarkupContent, Resp, TextEdit

_SOURCE = "LSP"
_LSP_ARTIFACTS = ARTIFACTS_DIR / "lsp.json"
_LSP: LSP = decode(LSP, loads(_LSP_ARTIFACTS.read_text("UTF-8")))
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


def _parse_item(item: CompletionItem) -> Completion:
    primary = _primary(item)
    secondaries = tuple(map(_range_edit, item.additionalTextEdits or ()))

    sort_by = item.filterText or ""
    kind = (
        _LSP.cmp_item_kind.lookup.get(item.kind, _LSP.cmp_item_kind.default)
        if item.kind
        else ""
    )
    label = f"{item.label} ({kind})" if kind else item.label

    doc, doc_type = _doc(item)

    cmp = Completion(
        source=_SOURCE,
        primary_edit=primary,
        secondary_edits=secondaries,
        sort_by=sort_by,
        label=label,
        doc=doc,
        doc_type=doc_type,
    )
    return cmp


def _parse(reply: Any) -> Tuple[bool, Sequence[Completion]]:
    try:
        resp: Resp = decode(Resp, reply, strict=False)
    except DecodeError:
        raise
    else:
        if isinstance(resp, CompletionList):
            return resp.isIncomplete, tuple(map(_parse_item, resp.items))
        elif isinstance(resp, Sequence):
            return False, tuple(map(_parse_item, resp))
        else:
            return False, ()


class Worker(BaseWorker[None]):
    def __init__(self, supervisor: Supervisor, misc: None) -> None:
        self._lock = Lock()
        self._sessions: MutableMapping[UUID, Future] = {}
        supervisor.nvim.api.exec_lua(_LUA, ())
        super().__init__(supervisor, misc=misc)

    def _req(self, session: UUID, pos: NvimPos) -> Any:
        token = uuid4()
        fut: Future = Future()

        with self._lock:
            self._sessions[token] = fut

        def cont() -> None:
            self._supervisor.nvim.api.exec_lua(
                "COQlsp_req(...)", (str(token), str(session), pos)
            )

        threadsafe_call(self._supervisor.nvim, cont)

        try:
            ret = fut.result(timeout=self._supervisor.options.timeout)
        except TimeoutError:
            ret = None

        with self._lock:
            if token in self._sessions:
                self._sessions.pop(token)
        return ret

    def notify(self, token: UUID, msg: Sequence[Any]) -> None:
        with self._lock:
            if token in self._sessions:
                reply, *_ = msg
                with suppress(InvalidStateError):
                    self._sessions[token].set_result(reply)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        session = uuid4()
        go = True

        while go:
            reply = self._req(session, pos=context.position)
            go, comps = _parse(reply)
            yield comps

