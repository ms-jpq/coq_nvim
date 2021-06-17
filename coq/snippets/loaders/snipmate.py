from os import linesep
from pathlib import Path
from string import whitespace
from textwrap import dedent
from typing import List, Set, Tuple

from .parse import opt_parse, raise_err
from .types import LoadSingle, MetaSnippet, Optional, Options

_COMMENT_START = "#"
_EXTENDS_START = "extends"
_SNIPPET_START = "snippet"
_SNIPPET_LINE_STARTS = {*whitespace}


def _parse_start(
    path: Path, lineno: int, line: str
) -> Tuple[str, Optional[str], Set[Options]]:
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
            '"',
            rest[third + 1 : fourth],
            opt_parse(rest[fourth + 1 :].strip()),
        )

    else:
        reason = f'Invaild # of " - {sep_count}'
        return raise_err(path, lineno=lineno, line=line, reason=reason)


def parse_one(path: Path) -> LoadSingle:
    snippets: List[MetaSnippet] = []
    extends: List[str] = []
    current_name = ""
    current_label: Optional[str] = None
    current_lines: List[str] = []

    def push() -> None:
        if current_name:
            content = dedent(linesep.join(current_lines))
            snippet = MetaSnippet(
                content=content,
                label=current_label,
                doc=None,
                matches={current_name},
                opts=set(),
            )
            snippets.append(snippet)

    lines = path.read_text().splitlines()
    for lineno, line in enumerate(lines, 1):
        if not line or line.isspace() or line.startswith(_COMMENT_START):
            pass

        elif line.startswith(_EXTENDS_START):
            filetypes = line[len(_EXTENDS_START) :].strip()
            for filetype in filetypes.split(","):
                extends.append(filetype.strip())

        elif line.startswith(_SNIPPET_START):
            push()
            current_name, current_label, current_opts = _parse_start(
                path, lineno=lineno, line=line
            )
            current_lines.clear()

        elif any(line.startswith(c) for c in _SNIPPET_LINE_STARTS):
            if current_name:
                current_lines.append(line)
            else:
                reason = "Expected snippet name"
                raise_err(path, lineno=lineno, line=line, reason=reason)

        else:
            reason = "Unexpected line start"
            raise_err(path, lineno=lineno, line=line, reason=reason)

    push()

    return snippets, extends

