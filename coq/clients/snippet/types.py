from typing import Any, Literal, Mapping, Sequence, TypedDict


class Artifacts(TypedDict):
    extends: Mapping[str, Mapping[str, Literal[True]]]
    snippets: Mapping[str, Sequence[Any]]

