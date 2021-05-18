from functools import cache
from os import linesep
from pathlib import Path

_SCRIPTS_PATH = Path(__file__).resolve().parent


@cache
def sql(*index: str) -> str:
    path = (_SCRIPTS_PATH / Path(*index)).with_suffix(".sql")
    lines = path.read_text("utf-8").splitlines()
    it = (line for line in lines if not line.startswith("--"))
    return linesep.join(it)
