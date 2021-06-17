from enum import Enum, auto
from os import linesep
from pathlib import Path
from typing import AbstractSet, MutableSequence, MutableSet, Optional, Tuple

from .parse import opt_parse, raise_err
from .types import ParsedSnippet, MetaSnippets, Options

_COMMENT_START = "#"
_EXTENDS_START = "extends"
_SNIPPET_START = "snippet"
_SNIPPET_END = "endsnippet"
_GLOBAL_START = "global"
_GLOBAL_END = "globalend"

_IGNORE_STARTS = {
    "priority",
    "iclearsnippets",
    "pre_expand",
    "post_expand",
    "post_jump",
}


class _State(Enum):
    normal = auto()
    snippet = auto()
    pglobal = auto()


def _start(
    path: Path, lineno: int, line: str
) -> Tuple[str, Optional[str], AbstractSet[Options]]:
    rest = line[len(_SNIPPET_START) :]
    sep_count = rest.count('"')

    if sep_count == 0:
        return rest.strip(), None, opt_parse("")

    if sep_count == 1:
        return rest.strip(), None, opt_parse("")

    elif sep_count == 2:
        first = rest.find('"')
        second = rest.find('"', first + 1)
        return (
            rest[:first].strip(),
            rest[first + 1 : second],
            opt_parse(rest[second + 1 :].strip()),
        )

    elif sep_count == 3:
        first = rest.find('"')
        second = rest.find('"', first + 1)
        third = rest.find('"', second + 1)
        return (
            '"',
            rest[second + 1 : third],
            opt_parse(rest[third + 1 :].strip()),
        )

    elif sep_count == 4:
        first = rest.find('"')
        second = rest.find('"', first + 1)
        third = rest.find('"', second + 1)
        fourth = rest.find('"', third + 1)
        return (
            rest[first:second],
            rest[third + 1 : fourth],
            opt_parse(rest[fourth + 1 :].strip()),
        )

    else:
        reason = f'Invaild # of " - {sep_count}'
        return raise_err(path, lineno=lineno, line=line, reason=reason)


def parse(path: Path) -> MetaSnippets:
    snippets: MutableSequence[ParsedSnippet] = []
    extends: MutableSet[str] = set()

    current_name = ""
    state = _State.normal
    current_label: Optional[str] = None
    current_lines: MutableSequence[str] = []
    current_opts: AbstractSet[Options] = frozenset()

    lines = path.read_text().splitlines()
    for lineno, line in enumerate(lines, 1):
        if state == _State.normal:
            if (
                not line
                or line.isspace()
                or line.startswith(_COMMENT_START)
                or any(line.startswith(ignore) for ignore in _IGNORE_STARTS)
            ):
                pass

            elif line.startswith(_EXTENDS_START):
                filetypes = line[len(_EXTENDS_START) :].strip()
                for filetype in filetypes.split(","):
                    extends.add(filetype.strip())

            elif line.startswith(_SNIPPET_START):
                state = _State.snippet

                current_name, current_label, current_opts = _start(
                    path, lineno=lineno, line=line
                )

            elif line.startswith(_GLOBAL_START):
                state = _State.pglobal

            else:
                reason = "Unexpected line start"
                raise_err(path, lineno=lineno, line=line, reason=reason)

        elif state == _State.snippet:
            if line.startswith(_SNIPPET_END):
                state = _State.normal

                content = linesep.join(current_lines)
                snippet = ParsedSnippet(
                    content=content,
                    label=current_label,
                    doc=None,
                    matches={current_name},
                    opts=current_opts,
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

    meta = MetaSnippets(snippets=snippets, extends=extends)
    return meta

