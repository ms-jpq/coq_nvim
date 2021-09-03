from difflib import get_close_matches
from hashlib import md5
from os import linesep
from os.path import splitext
from pathlib import PurePath
from string import whitespace
from textwrap import dedent
from typing import AbstractSet, Iterable, MutableSequence, MutableSet, Sequence, Tuple

from ..types import ParsedSnippet
from .parse import raise_err

_ALIAS_START = "alias"
_COMMENT_START = "#"
_EXTENDS_START = "extends"
_INCLUDES_START = "include"
_LABEL_START = "abbr"
_SNIPPET_LINE_STARTS = {*whitespace}
_SNIPPET_START = "snippet"

_IGNORED_STARTS = (
    "delete",
    "options",
    "regexp",
    "source",
)

_LEGAL_STARTS = {
    _ALIAS_START,
    _EXTENDS_START,
    _LABEL_START,
    _SNIPPET_START,
}


def _start(line: str) -> Tuple[str, str]:
    rest = line[len(_SNIPPET_START) :].strip()
    name, _, label = rest.partition(" ")
    if label.startswith('"') and label[1:].count('"') == 1:
        quoted, _, _ = label[1:].partition('"')
        return name, quoted
    else:
        return name, label


def parse(
    path: PurePath, lines: Iterable[Tuple[int, str]]
) -> Tuple[str, AbstractSet[str], Sequence[ParsedSnippet]]:
    source = PurePath(path.parent.parent.name) / path.parent.name
    filetype = path.stem

    snippets: MutableSequence[ParsedSnippet] = []
    extends: MutableSet[str] = set()

    current_name = ""
    current_label = ""
    current_aliases: MutableSequence[str] = []
    current_lines: MutableSequence[str] = []

    def push() -> None:
        if current_name:
            content = dedent(linesep.join(current_lines))
            snippet = ParsedSnippet(
                hash=md5(content.encode("UTF-8")).hexdigest(),
                source=source,
                grammar="snu",
                filetype=filetype,
                content=content,
                label=current_label,
                doc="",
                matches={*current_aliases},
            )
            snippets.append(snippet)

    for lineno, line in lines:
        line = line.rstrip()
        if (
            not line
            or line.isspace()
            or line.startswith(_COMMENT_START)
            or any(line.startswith(i) for i in _IGNORED_STARTS)
        ):
            pass

        elif line.startswith(_EXTENDS_START):
            filetypes = line[len(_EXTENDS_START) :].strip()
            for filetype in filetypes.split(","):
                extends.add(filetype.strip())

        elif line.startswith(_INCLUDES_START):
            ft = line[len(_INCLUDES_START) :].strip()
            filetype, _ = splitext(ft)
            extends.add(filetype)

        elif line.startswith(_SNIPPET_START):
            push()
            current_name, current_label = _start(line=line)
            current_lines.clear()
            current_aliases.clear()
            current_aliases.append(current_name)

        elif line.startswith(_ALIAS_START):
            current_aliases.append(line[len(_ALIAS_START) :].strip())

        elif line.startswith(_LABEL_START):
            current_label = line[len(_LABEL_START) :].strip()

        elif any(line.startswith(c) for c in _SNIPPET_LINE_STARTS):
            if current_name:
                current_lines.append(line)
            else:
                reason = "Expected snippet name"
                raise_err(path, lineno=lineno, line=line, reason=reason)

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

    push()

    return filetype, extends, snippets
