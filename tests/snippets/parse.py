from unittest import TestCase

from ...coq.ci.load import load


class Parser(TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._specs = load()

    def test_1(self) -> None:
        pass

