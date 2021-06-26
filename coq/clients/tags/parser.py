from dataclasses import dataclass
from typing import Iterator, Optional, Sequence

# https://en.wikipedia.org/wiki/Ctags

# Section Header
"""
\x0c
{src_file},{size_of_tag_definition_data_in_bytes}
"""

# Tag line
"""
{tag_definition_text}\x7f{tagname}\x01{line_number},{byte_offset}

Optional :: {tagname}\x01
"""

_SECTION_SEP = "\x0c"
_BYTE_SEP = ","
_DEF_SEP = "\x7f"
_LINE_NO_SEP = "\x01"


@dataclass(frozen=True)
class _Header:
    filename: str
    byte_len: int


@dataclass(frozen=True)
class _Tag:
    row: int
    col_offset: int
    name: Optional[str]
    text: str


@dataclass(frozen=True)
class _Section:
    header: _Header
    tags: Sequence[_Tag]


def _header(line: str) -> _Header:
    filename, sep, byte_len = line.rpartition(_BYTE_SEP)
    assert sep == _BYTE_SEP
    header = _Header(
        filename=filename,
        byte_len=int(byte_len),
    )
    return header


def _tag(line: str) -> _Tag:
    lhs, sep, col_offset = line.rpartition(_BYTE_SEP)
    assert sep == _BYTE_SEP
    text, sep, rhs = lhs.rpartition(_DEF_SEP)
    name, sep, row = rhs.rpartition(_LINE_NO_SEP)
    tag = _Tag(
        row=int(row),
        col_offset=int(col_offset),
        name=name or None,
        text=text,
    )
    return tag


def parse(text: str) -> Iterator[_Section]:
    sections = text.split(_SECTION_SEP)
    for section in sections:
        h_line, *t_lines = section.splitlines()
        header = _header(h_line)
        tags = tuple(map(_tag, t_lines))
        section = _Section(
            header=header,
            tags=tags,
        )
        yield section

