from json import loads
from subprocess import DEVNULL, CalledProcessError, check_output
from typing import Iterator, Optional, TypedDict


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


def run(*args: str) -> str:
    if not args:
        return ""
    else:
        try:
            raw = check_output(
                (
                    "ctags",
                    "--sort=no",
                    "--output-format=json",
                    f"--fields={_FIELDS}",
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
        json = loads(line)
        if json["_type"] == "tag":
            yield json

