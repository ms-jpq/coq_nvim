from json import loads
from pathlib import PurePath
from subprocess import DEVNULL, CalledProcessError, check_output
from typing import Iterator, Optional, Sequence, TypedDict

from std2.pathlib import AnyPath


class Tag(TypedDict):
    language: str
    path: str
    line: int
    name: str

    kind: Optional[str]
    typeref: Optional[str]
    scopeKind: Optional[str]
    access: Optional[str]


_FIELDS = "".join(
    f"{f}"
    for f in (
        "language",
        "input",
        "line",
        "kind",
        "typeref",
        "scopeKind",
        "access",
        "name",
    )
)


def run(*args: str, cwd: AnyPath) -> str:
    try:
        raw = check_output(
            (
                "ctags",
                "--sort=no",
                "--output-format=json",
                f"--fields={_FIELDS}",
                *args,
            ),
            cwd=cwd,
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
        json = loads(line)
        if json["_type"] == "tag":
            yield json


def parse(paths: Sequence[PurePath]) -> Sequence[Tag]:
    if not paths:
        return ()
    else:
        raw = run(*map(str, paths), cwd=".")
        return tuple(parse_lines(raw))

