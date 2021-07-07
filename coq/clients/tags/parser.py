from json import loads
from json.decoder import JSONDecodeError
from subprocess import DEVNULL, CalledProcessError, check_output
from typing import Iterator, Optional, TypedDict

from pynvim_pp.logging import log
from std2.asyncio import call
from std2.string import removeprefix, removesuffix


class Tag(TypedDict):
    language: str

    path: str

    line: int
    name: str
    pattern: str
    kind: str

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
        "kind",
        "name",
        "pattern",
        "typeref",
        "scope",
        "scopeKind",
        "access",
        "signature",
    )
)


async def run(*args: str) -> str:
    if not args:
        return ""
    else:
        proc = await call(
            "ctags",
            "--sort=no",
            "--output-format=json",
            f"--fields={_FIELDS}",
            *args,
        )
        return proc.out.decode()


def _unescape(pattern: str) -> str:
    def cont() -> Iterator[str]:
        stripped = removesuffix(removeprefix(pattern[1:-1], "^"), "$").strip()
        it = iter(stripped)
        for c in it:
            if c == "\\":
                nc = next(it, "")
                if nc in {"/", "\\"}:
                    yield nc
            else:
                yield c

    return "".join(cont())


def parse_lines(raw: str) -> Iterator[Tag]:
    for line in raw.splitlines():
        if line:
            try:
                json = loads(line)
            except JSONDecodeError:
                log.exception("%s", line)
                raise
            if json["_type"] == "tag":
                json["pattern"] = _unescape(json["pattern"])
                yield json

