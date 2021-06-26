from subprocess import check_call
from unittest import TestCase

from ....coq.clients.tags.parser import parse
from ....coq.consts import TAGS_DIR, TOP_LEVEL


class Parser(TestCase):
    def test_1(self) -> None:
        tag = TAGS_DIR / "TAG"
        TAGS_DIR.mkdir(parents=True, exist_ok=True)
        if not tag.exists():
            check_call(("etags", "--recurse", "-o", str(tag)), cwd=TOP_LEVEL)

        spec = tag.read_text()
        tuple(parse(spec, raise_err=True))

