from typing import Sequence, TypedDict


class Payload(TypedDict):
    kind: str
    text: str


Msg = Sequence[Payload]

