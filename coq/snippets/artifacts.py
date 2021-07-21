from json import loads

from ..consts import SNIPPET_ARTIFACTS
from .types import ASnips

SNIPPETS: ASnips = loads(SNIPPET_ARTIFACTS.read_text("UTF-8"))

