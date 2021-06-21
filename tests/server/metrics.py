from unittest import TestCase

from ...coq.server.metrics import count


class Matcher(TestCase):
    def test_1(self) -> None:
        cword = "in"
        match = "_from_each_according_to_their_ability"
        c = count(cword, match=match)
        print(c)

