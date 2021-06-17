from json import loads
from os import linesep
from pathlib import Path
from typing import Dict, List, Sequence, Set, Union, cast

from .types import LoadSingle, MetaSnippet


def _prefix_parse(prefix: Union[str, Sequence[str]]) -> Set[str]:
    if type(prefix) is str:
        return {cast(str, prefix)}
    elif type(prefix) is list:
        return {*cast(List[str], prefix)}
    else:
        raise ValueError(prefix)


def _body_parse(body: Union[str, Sequence[str]]) -> str:
    if type(body) is str:
        return cast(str, body)
    elif type(body) is list:
        return linesep.join(cast(List, body))
    else:
        raise ValueError(body)


def parse_one(path: Path) -> LoadSingle:
    snippets: List[MetaSnippet] = []
    text = path.read_text("UTF-8") if path.exists() else ""
    json = loads(text)

    for label, values in cast(Dict[str, Dict[str, str]], json).items():
        snippet = MetaSnippet(
            content=_body_parse(values["body"]),
            label=label,
            doc=values.get("description"),
            matches=_prefix_parse(values["prefix"]),
            opts=set(),
        )
        snippets.append(snippet)

    return snippets, []

