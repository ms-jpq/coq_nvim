from random import uniform
from unittest import TestCase

from ...coq.server.reviewer import sigmoid


class Sigmoid(TestCase):
    def test_1(self) -> None:
        y = sigmoid(0)
        self.assertEqual(y, 1)

    def test_2(self) -> None:
        for _ in range(0, 10000):
            y = sigmoid(uniform(-10, 10))
            self.assertTrue(y >= 0.5 and y <= 1.5)
