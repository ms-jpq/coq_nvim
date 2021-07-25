from asyncio.events import AbstractEventLoop
from concurrent.futures import Executor
from contextlib import suppress
from hashlib import md5
from json import dumps, loads
from json.decoder import JSONDecodeError
from pathlib import Path
from shutil import move
from tempfile import NamedTemporaryFile
from typing import (
    AbstractSet,
    Any,
    Iterable,
    Mapping,
    MutableMapping,
    MutableSequence,
    Tuple,
    TypedDict,
    cast,
)

from std2.asyncio import run_in_executor
from std2.pathlib import is_relative_to

from ...consts import CLIENTS_DIR, TMP_DIR
from ...shared.lru import LRU
from ...shared.timeit import timeit
from .parser import Tag, parse_lines, run

_TAGS_DIR = CLIENTS_DIR / "tags"


class _TagInfo(TypedDict):
    mtime: float
    lang: str
    tags: MutableSequence[Tag]


Tags = Mapping[str, _TagInfo]


def _mtimes(cwd: Path, paths: Iterable[Path]) -> Mapping[str, float]:
    def cont() -> Iterable[Tuple[Path, float]]:
        for path in paths:
            if is_relative_to(path, cwd):
                with suppress(FileNotFoundError):
                    stat = path.stat()
                    yield path, stat.st_mtime

    return {str(key): val for key, val in cont()}


def _load(path: Path) -> Tags:
    try:
        json = path.read_text("UTF-8")
    except FileNotFoundError:
        return {}
    else:
        try:
            tags = loads(json)
        except JSONDecodeError:
            return {}
        else:
            return cast(Tags, tags)


def _dump(path: Path, o: Any) -> None:
    json = dumps(o, check_circular=False, ensure_ascii=False)
    with suppress(FileNotFoundError):
        with NamedTemporaryFile(dir=TMP_DIR) as tmp:
            tmp.write(json.encode("UTF-8"))
            tmp.flush()
            move(tmp.name, path)


_LRU = LRU[Path, Any](size=3)


async def reconciliate(
    loop: AbstractEventLoop, ppool: Executor, cwd: Path, paths: AbstractSet[str]
) -> Tags:
    _TAGS_DIR.mkdir(parents=True, exist_ok=True)
    tags_path = _TAGS_DIR / md5(str(cwd).encode()).hexdigest()

    existing = _LRU.get(tags_path) or await loop.run_in_executor(
        ppool, _load, tags_path
    )

    mtimes = await run_in_executor(
        _mtimes, cwd, paths=map(Path, existing.keys() | paths)
    )
    query_paths = tuple(
        path
        for path, mtime in mtimes.items()
        if mtime > existing.get(path, _TagInfo(mtime=0, lang="", tags=[]))["mtime"]
    )
    raw = await run(*query_paths) if query_paths else ""

    acc: MutableMapping[str, _TagInfo] = {}
    async for tag in parse_lines(raw):
        path = tag["path"]
        info = acc.setdefault(
            path, _TagInfo(mtime=mtimes.get(path, 0), lang="", tags=[])
        )
        info["lang"] = tag["language"]
        info["tags"].append(tag)

    if acc:
        new = {**{key: val for key, val in existing.items() if key in mtimes}, **acc}
        await loop.run_in_executor(ppool, _dump, tags_path, new)
        _LRU[tags_path] = new
    else:
        new = existing
    return new

