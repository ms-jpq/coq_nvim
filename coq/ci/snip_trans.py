from dataclasses import replace

from std2.string import removesuffix

from ..snippets.types import ParsedSnippet


def trans(snip: ParsedSnippet) -> ParsedSnippet:
    if snip.filetype in {"javascript", "typescript", "typescriptreact"}:
        content = removesuffix(snip.content, suffix=";")
        return replace(snip, content=content)
    else:
        return snip
