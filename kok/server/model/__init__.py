from functools import cache
from pathlib import Path

_SCRIPTS_PATH = Path(__file__).resolve().parent / "sql"


@cache
def load(name: str) -> str:
    return (_SCRIPTS_PATH / name).with_suffix(".sql").read_text()
