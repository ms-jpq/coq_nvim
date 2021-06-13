from concurrent.futures import CancelledError, Future, InvalidStateError
from contextlib import suppress
from json import loads
from threading import Lock
from typing import Any, Iterator, MutableMapping, Sequence, Tuple
from uuid import UUID, uuid4

from pynvim import Nvim
from std2.pickle import DecodeError, decode

from ...consts import ARTIFACTS_DIR
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context, Edit, NvimPos, RangeEdit
from .runtime import LSP
from .types import CompletionItem, CompletionList, MarkupContent, Resp, TextEdit

_LSP_ARTIFACTS = ARTIFACTS_DIR / "lsp.json"

_LSP: LSP = decode(LSP, loads(_LSP_ARTIFACTS.read_text("UTF-8")))


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
    label = item.label
    short_label = (
        _LSP.cmp_item_kind.lookup.get(item.kind, _LSP.cmp_item_kind.default)
        if item.kind
        else ""
    )

    doc, doc_type = _doc(item)

    cmp = Completion(
        primary_edit=primary,
        secondary_edits=secondaries,
        sort_by=sort_by,
        label=label,
        short_label=short_label,
        doc=doc,
        doc_type=doc_type,
    )
    return cmp


def _parse(pos: NvimPos, reply: Any) -> Tuple[bool, Sequence[Completion]]:
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


def _req(nvim: Nvim, token: UUID, pos: NvimPos) -> Resp:
    nvim.api.exec_lua("")


class Worker(BaseWorker[None]):
    def __init__(self, supervisor: Supervisor, misc: None) -> None:
        self._lock = Lock()
        self._pending: MutableMapping[UUID, Future] = {}
        super().__init__(supervisor, misc=misc)

    def notify(self, token: UUID, msg: Sequence[Any]) -> None:
        with self._lock:
            if token in self._pending:
                reply, *_ = msg
                with suppress(InvalidStateError):
                    self._pending[token].set_result(reply)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        yield ()

        token = uuid4()
        fut: Future = Future()

        def cont(fut: Future) -> None:
            with self._lock:
                if token in self._pending:
                    self._pending.pop(token)
            try:
                ret = fut.result()
            except CancelledError:
                pass

        fut.add_done_callback(cont)
        with self._lock:
            self._pending[token] = fut

        _req(self._supervisor.nvim, token=token, pos=context.position)

