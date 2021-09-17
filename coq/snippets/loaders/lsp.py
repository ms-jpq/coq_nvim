from dataclasses import dataclass
from json import loads
from pathlib import PurePath
from typing import AbstractSet, Iterable, Iterator, Mapping, Sequence, Tuple, Union

from std2.pickle import new_decoder

from ...shared.types import SnippetGrammar
from ..consts import SNIP_LINE_SEP
from ..types import ParsedSnippet


@dataclass
class _Unit:
    body: Union[str, Sequence[str]]
    prefix: Union[str, Sequence[str], None] = None
    description: Union[str, Sequence[str]] = ""


_DECODER = new_decoder[Mapping[str, _Unit]](Mapping[str, _Unit], strict=False)


def _prefix(prefix: Union[str, Sequence[str], None], content: str) -> AbstractSet[str]:
    if prefix is None:
        return {content}
    elif isinstance(prefix, str):
        return {prefix.strip()}
    elif isinstance(prefix, Sequence):
        return {p.strip() for p in prefix}
    else:
        assert False


def _body(body: Union[str, Sequence[str]]) -> str:
    if isinstance(body, str):
        return body
    elif isinstance(body, Sequence):
        return SNIP_LINE_SEP.join(body)
    else:
        assert False


def load_lsp(
    grammar: SnippetGrammar, path: PurePath, lines: Iterable[Tuple[int, str]]
) -> Tuple[str, AbstractSet[str], Sequence[ParsedSnippet]]:
    filetype = path.stem.strip()

    text = SNIP_LINE_SEP.join(line.rstrip() for _, line in lines)
    json = loads(text)
    fmt = _DECODER(json)

    def cont() -> Iterator[ParsedSnippet]:
        for label, values in fmt.items():
            content = _body(values.body).strip()
            matches = _prefix(values.prefix, content=content)
            doc = _body(values.description).strip()
            snippet = ParsedSnippet(
                grammar=grammar,
                filetype=filetype,
                content=content,
                doc=doc,
                label=label,
                matches=matches,
            )
            yield snippet

    return filetype, set(), tuple(cont())
