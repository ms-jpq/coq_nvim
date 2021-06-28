from unittest import TestCase

from ...coq.server.reviewer import count


class Matcher(TestCase):
    def test_1(self) -> None:
        cword = "ab"
        match = "abab"
        c = count({}, cword=cword, match=match)
        self.assertEqual(c.prefix_matches, 2)
        self.assertEqual(c.num_matches, 2)
        self.assertEqual(c.consecutive_matches, 1)

