from json import loads
from json.decoder import JSONDecodeError
from typing import Iterator, Mapping, MutableMapping, MutableSequence, Tuple

from pynvim_pp.lib import decode
from pynvim_pp.logging import log
from std2.asyncio.subprocess import call
from std2.string import removeprefix, removesuffix

from .types import Tag, Tags

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
        try:
            proc = await call(
                "ctags",
                "--sort=no",
                "--output-format=json",
                f"--fields={_FIELDS}",
                *args,
                check_returncode=set(),
            )
        except (FileNotFoundError, PermissionError):
            return ""
        else:
            return decode(proc.stdout)


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


def parse(mtimes: Mapping[str, float], raw: str) -> Tags:
    tags: MutableMapping[str, Tuple[str, float, MutableSequence[Tag]]] = {}

    for line in raw.splitlines():
        if line:
            try:
                json = loads(line)
            except JSONDecodeError:
                log.warning("%s", line)
            else:
                if json["_type"] == "tag":
                    path = json["path"]
                    json["pattern"] = _unescape(json["pattern"])
                    _, _, acc = tags.setdefault(
                        path, (json["language"], mtimes.get(path, 0), [])
                    )
                    acc.append(json)

    return tags
