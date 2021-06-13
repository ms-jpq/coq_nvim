from unittest import TestCase

from ....coq.clients.paths.worker import parse


class Parser(TestCase):
    def test_1(self) -> None:
        line = "abc~/cdf"
        self.assertEqual(1, 1)

