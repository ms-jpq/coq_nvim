from typing import Mapping, Optional, Sequence, Tuple, TypedDict


class Tag(TypedDict):
    language: str

    path: str

    line: int
    name: str
    pattern: str
    kind: str

    typeref: Optional[str]

    scope: Optional[str]
    scopeKind: Optional[str]

    access: Optional[str]


Tags = Mapping[str, Tuple[str, float, Sequence[Tag]]]
