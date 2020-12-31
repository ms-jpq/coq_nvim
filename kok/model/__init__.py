from functools import cache
from pathlib import Path

_SCRIPTS_PATH = Path(__file__).resolve().parent


@cache
def load(name: str) -> str:
    return (_SCRIPTS_PATH / name).read_text()
