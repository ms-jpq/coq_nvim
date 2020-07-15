from json import load
from typing import Any


def load_json(path: str) -> Any:
    with open(path) as fd:
        return load(fd)
