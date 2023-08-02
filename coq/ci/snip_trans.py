from dataclasses import replace
from re import RegexFlag, compile

from ..snippets.types import ParsedSnippet

_JS = compile(r";\s?$", flags=RegexFlag.MULTILINE)


def trans(snip: ParsedSnippet) -> ParsedSnippet:
    if snip.filetype in {"javascript", "typescript", "typescriptreact"}:
        content = _JS.sub("", snip.content)
        return replace(snip, content=content)
    else:
        return snip
