from unittest import TestCase

from ...coq.shared.parse import match


class Match(TestCase):
    def test_1(self) -> None:
        existing = ""
        insertion = ""
        m = match(False, existing=existing, insertion=insertion)
        self.assertEquals(m, "")

