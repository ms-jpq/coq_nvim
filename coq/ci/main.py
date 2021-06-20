from json import dumps

from std2.pickle import encode
from std2.tree import recur_sort

from ..consts import SNIPPET_ARTIFACTS
from .load import load_parsable


def main() -> None:
    parsed = load_parsable()
    ordered = recur_sort(encode(parsed))
    json = dumps(ordered, check_circular=False, ensure_ascii=False, indent=2)
    SNIPPET_ARTIFACTS.write_text(json)

