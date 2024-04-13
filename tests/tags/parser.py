from itertools import islice
from os import linesep
from pathlib import Path
from shutil import get_terminal_size, which
from sys import stderr
from unittest import IsolatedAsyncioTestCase

from ...coq.consts import TMP_DIR
from ...coq.tags.parse import parse, run


class Parser(IsolatedAsyncioTestCase):
    async def test_1(self) -> None:
        tag = TMP_DIR / "TAG"
        TMP_DIR.mkdir(parents=True, exist_ok=True)
        if not tag.exists() and (ctags := which("ctags")):
            text = await run(Path(ctags), "--recurse")
            tag.write_text(text)

        spec = tag.read_text()
        parsed = parse({}, raw=spec)

        cols, _ = get_terminal_size()
        sep = linesep + "-" * cols + linesep
        print(
            *islice((tag for _, _, tags in parsed.values() for tag in tags), 10),
            sep=sep,
            file=stderr,
        )
