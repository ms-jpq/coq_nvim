from unittest import TestCase


class DoubleEndedIterator(TestCase):
    def test_1(self) -> None:
        t1 = (1, 2, 3, 4, 5)
        d1 = deiter(t1)
        t2 = tuple(d1)
        self.assertEqual(t1, t2)
