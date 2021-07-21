from json import loads

from ..consts import SNIPPET_ARTIFACTS
from ..shared.timeit import timeit
from .types import ASnips

with timeit("LOAD-SNIPS"):
    SNIPPETS: ASnips = loads(SNIPPET_ARTIFACTS.read_text("UTF-8"))

