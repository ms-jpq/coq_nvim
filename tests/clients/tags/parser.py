from itertools import islice
from os import linesep
from shutil import get_terminal_size
from unittest import TestCase

from ....coq.clients.tags.parser import _parse_lines, run
from ....coq.consts import TMP_DIR, TOP_LEVEL


class Parser(TestCase):
    def test_1(self) -> None:
        tag = TMP_DIR / "TAG"
        TMP_DIR.mkdir(parents=True, exist_ok=True)
        if not tag.exists():
            text = run("--recurse", cwd=TOP_LEVEL)
            tag.write_text(text)

        spec = tag.read_text()
        parsed = tuple(_parse_lines(spec))

        cols, _ = get_terminal_size()
        sep = linesep + "-" * cols + linesep
        print(*islice(parsed, 10), sep=sep)

