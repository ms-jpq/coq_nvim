from functools import cache
from pathlib import Path
from string import Template

_SCRIPTS_PATH = Path(__file__).resolve().parent


@cache
def sql(*index: str) -> str:
    path = (_SCRIPTS_PATH / Path(*index)).with_suffix(".sql")
    text = path.read_text("utf-8")
    return text


@cache
def sqlt(*index: str) -> Template:
    text = sql(*index)
    return Template(text)

