from typing import Iterator

from .types import Header, Section, Tag

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


def _header(line: str) -> Header:
    filename, sep, byte_len = line.rpartition(_BYTE_SEP)
    assert sep == _BYTE_SEP, line
    header = Header(
        filename=filename,
        byte_len=int(byte_len),
    )
    return header


def _tag(line: str) -> Tag:
    lhs, sep, col_offset = line.rpartition(_BYTE_SEP)
    assert sep == _BYTE_SEP, line
    text, sep, rhs = lhs.rpartition(_DEF_SEP)
    name, sep, row = rhs.rpartition(_LINE_NO_SEP)
    tag = Tag(
        row=int(row),
        col_offset=int(col_offset),
        name=name or None,
        text=text,
    )
    return tag


def parse(text: str) -> Iterator[Section]:
    sections = text.split(_SECTION_SEP)
    for section in sections:
        lines = section.splitlines()
        if lines:
            h_line, *t_lines = (line for line in lines if line)
            header = _header(h_line)
            tags = tuple(map(_tag, t_lines))
            sec = Section(
                header=header,
                tags=tags,
            )
            yield sec

