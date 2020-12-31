from dataclasses import dataclass


@dataclass(frozen=True)
class Position:
    row: int
    col: int


# |...                            line                            ...|
# |...        line_before          🐭          line_after         ...|
# |...   <syms_before><words_before>🐭<words_after><syms_after>   ...|
@dataclass(frozen=True)
class Context:
    filename: str
    filetype: str

    position: Position

    line: str
    line_normalized: str
    line_before: str
    line_before_normalized: str
    line_after: str
    line_after_normalized: str

    words: str
    words_normalized: str
    words_before: str
    words_before_normalized: str
    words_after: str
    words_after_normalized: str

    syms: str
    syms_before: str
    syms_after: str

    words_syms: str
    words_syms_normalized: str
    words_syms_before: str
    words_syms_before_normalized: str
    words_syms_after: str
    words_syms_after_normalized: str


@dataclass(frozen=True)
class SEdit:
    new_text: str


@dataclass(frozen=True)
class MEdit:
    old_prefix: str
    new_prefix: str
    old_suffix: str
    new_suffix: str


# end exclusve
@dataclass(frozen=True)
class LEdit:
    begin: Position
    end: Position
    new_text: str


@dataclass(frozen=True)
class Snippet:
    kind: str
    match: str
    content: str
