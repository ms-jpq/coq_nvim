from functools import cache
from os import linesep
from pathlib import Path

_SCRIPTS_PATH = Path(__file__).resolve().parent / "sql"


@cache
def load(name: str) -> str:
    lines = (_SCRIPTS_PATH / name).with_suffix(".sql").read_text().splitlines()
    return linesep.join(line for line in lines if not line.startswith("--"))
