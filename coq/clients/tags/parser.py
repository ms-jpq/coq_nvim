from concurrent.futures import Executor
from json import loads
from pathlib import Path
from subprocess import DEVNULL, CalledProcessError, check_output
from typing import Iterator, Mapping, Optional, Sequence, TypedDict


class Tag(TypedDict):
    language: str

    path: str

    line: int
    name: str
    pattern: str

    roles: Optional[str]
    kind: Optional[str]
    typeref: Optional[str]

    scope: Optional[str]
    scopeKind: Optional[str]

    access: Optional[str]


_FIELDS = "".join(
    f"{{{f}}}"
    for f in (
        "language",
        "input",
        "line",
        "name",
        "roles",
        "kind",
        "typeref",
        "scope",
        "scopeKind",
        "access",
        "signature",
    )
)


def run(*args: str, cwd: Path) -> str:
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


def parse(pool: Executor, paths: Sequence[Path], cwd: Path) -> Mapping[str, Tag]:
    if not paths:
        return {}
    else:
        raw = run(*map(str, paths), cwd=cwd)
        return tuple(parse_lines(raw))

