from unittest import TestCase

from ....coq.clients.paths.worker import parse


class Parser(TestCase):
    def test_1(self) -> None:
        line = "./.gith"
        actual = tuple(parse(line))
        expected = (("./.gith", "./.github"),)
        self.assertEqual(actual, expected)

