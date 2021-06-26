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
    if sep != _BYTE_SEP:
        raise ValueError(line)
    header = _Header(
        filename=filename,
        byte_len=int(byte_len),
    )
    return header


def _tag(line: str) -> _Tag:
    lhs, sep, col_offset = line.rpartition(_BYTE_SEP)
    if sep != _BYTE_SEP:
        raise ValueError(line)

    text, sep, rhs = lhs.rpartition(_DEF_SEP)
    name, sep, row = rhs.rpartition(_LINE_NO_SEP)
    tag = _Tag(
        row=int(row),
        col_offset=int(col_offset),
        name=name or None,
        text=text,
    )
    return tag


def parse(text: str, raise_err: bool) -> Iterator[_Section]:
    sections = text.split(_SECTION_SEP)
    for section in sections:
        if section:
            try:
                h_line, *t_lines = (line for line in section.splitlines() if line)
                header = _header(h_line)
                tags = tuple(map(_tag, t_lines))
                sec = _Section(
                    header=header,
                    tags=tags,
                )
                yield sec
            except ValueError:
                if raise_err:
                    raise

