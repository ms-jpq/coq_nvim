from difflib import get_close_matches
from enum import Enum, auto
from pathlib import PurePath
from typing import AbstractSet, Iterable, MutableSequence, MutableSet, Sequence, Tuple

from ...shared.types import SnippetGrammar
from ..consts import SNIP_LINE_SEP
from ..types import ParsedSnippet
from .parse import raise_err

_COMMENT_START = "#"
_EXTENDS_START = "extends"
_GLOBAL_END = "globalend"
_GLOBAL_START = "global"
_SNIPPET_END = "endsnippet"
_SNIPPET_START = "snippet"

_IGNORE_STARTS = {
    "iclearsnippets",
    "post_expand",
    "post_jump",
    "pre_expand",
    "priority",
}

_LEGAL_STARTS = {
    _EXTENDS_START,
    _GLOBAL_END,
    _GLOBAL_START,
    _SNIPPET_END,
    _SNIPPET_START,
}


class _State(Enum):
    normal = auto()
    snippet = auto()
    pglobal = auto()


def _start(line: str) -> Tuple[str, str]:
    rest = line[len(_SNIPPET_START) :].strip()
    name, _, label = rest.partition(" ")
    if label.startswith('"') and label[1:].count('"') == 1:
        quoted, _, _ = label[1:].partition('"')
        return name, quoted
    else:
        return name, label


def load_ultisnip(
    grammar: SnippetGrammar, path: PurePath, lines: Iterable[Tuple[int, str]]
) -> Tuple[str, AbstractSet[str], Sequence[ParsedSnippet]]:
    filetype = path.stem.strip()

    snippets: MutableSequence[ParsedSnippet] = []
    extends: MutableSet[str] = set()

    current_name = ""
    state = _State.normal
    current_label = ""
    current_lines: MutableSequence[str] = []

    for lineno, line in lines:
        line = line.rstrip()

        if state == _State.normal:
            if line.startswith(_COMMENT_START) or any(
                line.startswith(ignore) for ignore in _IGNORE_STARTS
            ):
                pass

            elif not line or line.isspace():
                current_lines.append("")

            elif line.startswith(_EXTENDS_START):
                filetypes = line[len(_EXTENDS_START) :].strip()
                for ft in (f.strip() for f in filetypes.split(",")):
                    if ft:
                        extends.add(ft)

            elif line.startswith(_SNIPPET_START):
                state = _State.snippet

                current_name, current_label = _start(line)

            elif line.startswith(_GLOBAL_START):
                state = _State.pglobal

            else:
                start, _, _ = line.partition(" ")
                close = get_close_matches(start, _LEGAL_STARTS, n=1)
                if close:
                    maybe_start, *_ = close
                    addendum = f" :: did you mean -- {maybe_start}"
                else:
                    addendum = ""

                reason = "Unexpected line start" + addendum
                raise_err(path, lineno=lineno, line=line, reason=reason)

        elif state == _State.snippet:
            if line.startswith(_SNIPPET_END):
                state = _State.normal

                content = SNIP_LINE_SEP.join(current_lines)
                snippet = ParsedSnippet(
                    grammar=grammar,
                    filetype=filetype,
                    content=content,
                    label=current_label,
                    doc="",
                    matches={current_name},
                )
                snippets.append(snippet)
                current_lines.clear()

            else:
                current_lines.append(line)

        elif state == _State.pglobal:
            if line.startswith(_GLOBAL_END):
                state = _State.normal
            else:
                pass

        else:
            assert False

    return filetype, extends, snippets
