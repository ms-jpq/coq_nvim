from functools import cache
from os.path import realpath, dirname


_SCRIPTS_PATH = dirname(realpath(__file__))


@cache
def load(name: str) -> str:
    pass
