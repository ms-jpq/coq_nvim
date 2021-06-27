from dataclasses import dataclass
from pathlib import PurePath
from subprocess import DEVNULL, CalledProcessError, check_output
from typing import Iterator, Sequence


@dataclass(frozen=True)
class Tag:
    filename: str
    line_num: int
    context: str
    kind: str
    name: str


_SEP = "\x04"

FMT = f"""
%{{input}}{_SEP}%{{line}}{_SEP}%{{compact}}{_SEP}%{{kind}}{_SEP}%{{name}}
""".strip()


def run(
    *args: str,
) -> str:
    try:
        raw = check_output(
            (
                "ctags",
                "--sort=no",
                "--output-format=xref",
                f"--_xformat={FMT}",
                *args,
            ),
            text=True,
            stdin=DEVNULL,
            stderr=DEVNULL,
        )
    except CalledProcessError:
        return ""
    else:
        return raw


def parse_lines(raw: str) -> Iterator[Tag]:
    for line in raw.splitlines():
        filename, line_num, context, kind, name = line.split(_SEP)
        tag = Tag(
            filename=filename,
            line_num=int(line_num),
            context=context,
            kind=kind,
            name=name,
        )
        yield tag


def parse(paths: Sequence[PurePath]) -> Sequence[Tag]:
    if not paths:
        return ()
    else:
        raw = run(*map(str, paths))
        return tuple(parse_lines(raw))

