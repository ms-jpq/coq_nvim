from unittest import TestCase

from ....coq.clients.t9.worker import sort_by


class SortBy(TestCase):
    def test_1(self) -> None:
        s = sort_by(set(), "abc|")
        self.assertEqual(s, "|")

    def test_2(self) -> None:
        s = sort_by(set(), "|abc")
        self.assertEqual(s, "|abc")
