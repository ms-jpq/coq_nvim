from itertools import islice
from os import linesep
from shutil import get_terminal_size
from unittest import IsolatedAsyncioTestCase

from ....coq.clients.tags.parser import parse_lines, run
from ....coq.consts import TMP_DIR


class Parser(IsolatedAsyncioTestCase):
    async def test_1(self) -> None:
        tag = TMP_DIR / "TAG"
        TMP_DIR.mkdir(parents=True, exist_ok=True)
        if not tag.exists():
            text = await run("--recurse")
            tag.write_text(text)

        spec = tag.read_text()
        parsed = [tag async for tag in parse_lines(spec)]

        cols, _ = get_terminal_size()
        sep = linesep + "-" * cols + linesep
        print(*islice(parsed, 10), sep=sep)

