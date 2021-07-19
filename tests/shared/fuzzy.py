from unittest import TestCase

from ...coq.shared.fuzzy import count, quick_ratio


class QuickRatio(TestCase):
    def test_1(self) -> None:
        lhs = "a"
        rhs = "ab"
        ratio = quick_ratio(lhs, rhs)
        self.assertAlmostEqual(ratio, 1)


class Metrics(TestCase):
    def test_1(self) -> None:
        cword = "ab"
        match = "abab"
        c = count(cword, match=match)
        self.assertEqual(c.prefix_matches, 2)
        self.assertEqual(c.num_matches, 2)
        self.assertEqual(c.consecutive_matches, 1)

