from itertools import islice
from os import linesep
from shutil import get_terminal_size
from unittest import IsolatedAsyncioTestCase

from ...coq.consts import TMP_DIR
from ...coq.tags.parse import parse, run


class Parser(IsolatedAsyncioTestCase):
    async def test_1(self) -> None:
        tag = TMP_DIR / "TAG"
        TMP_DIR.mkdir(parents=True, exist_ok=True)
        if not tag.exists():
            text = await run("--recurse")
            tag.write_text(text)

        spec = tag.read_text()
        parsed = parse({}, raw=spec)

        cols, _ = get_terminal_size()
        sep = linesep + "-" * cols + linesep
        print(
            *islice((tag for _, _, tags in parsed.values() for tag in tags), 10),
            sep=sep
        )

