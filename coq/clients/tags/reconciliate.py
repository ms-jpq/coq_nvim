from contextlib import suppress
from hashlib import md5
from json import dumps, loads
from pathlib import Path
from typing import (
    AbstractSet,
    Iterable,
    Mapping,
    MutableMapping,
    MutableSequence,
    Tuple,
    TypedDict,
)

from ...consts import CLIENTS_DIR
from .parser import Tag, parse_lines, run

_TAGS_DIR = CLIENTS_DIR / "tags"


class _TagInfo(TypedDict):
    mtime: float
    lang: str
    tags: MutableSequence[Tag]


Tags = Mapping[str, _TagInfo]


def _mtimes(paths: Iterable[Path]) -> Mapping[str, float]:
    def cont() -> Iterable[Tuple[Path, float]]:
        for path in paths:
            with suppress(FileNotFoundError):
                stat = path.stat()
                yield path, stat.st_mtime

    return {str(key): val for key, val in cont()}


def reconciliate(cwd: Path, paths: AbstractSet[str]) -> Tags:
    _TAGS_DIR.mkdir(parents=True, exist_ok=True)
    tags_path = _TAGS_DIR / md5(str(cwd).encode()).hexdigest()

    try:
        json = tags_path.read_text("UTF-8")
    except FileNotFoundError:
        existing: Tags = {}
    else:
        existing = loads(json)

    mtimes = _mtimes(map(Path, existing.keys() | paths))
    query_paths = tuple(
        path
        for path, mtime in mtimes.items()
        if mtime > existing.get(path, _TagInfo(mtime=0, lang="", tags=[]))["mtime"]
    )
    raw = run(*query_paths) if query_paths else ""

    acc: MutableMapping[str, _TagInfo] = {}
    for tag in parse_lines(raw):
        path = tag["path"]
        info = acc.setdefault(
            path, _TagInfo(mtime=mtimes.get(path, 0), lang="", tags=[])
        )
        info["lang"] = tag["language"]
        info["tags"].append(tag)

    new = {**{key: val for key, val in existing if key in mtimes}, **acc}
    json = dumps(new, check_circular=False, ensure_ascii=False, indent=2)
    tags_path.write_text(json)
    return new

