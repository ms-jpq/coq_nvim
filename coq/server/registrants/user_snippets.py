from locale import strxfrm
from os.path import normcase
from pathlib import PurePath
from typing import AbstractSet, Any, Iterable, Iterator, Mapping, Sequence, Tuple

from pynvim.api.nvim import Nvim
from pynvim_pp.api import buf_get_lines, buf_line_count, buf_name, cur_win, win_get_buf
from pynvim_pp.hold import hold_win_pos
from pynvim_pp.lib import write
from pynvim_pp.operators import operator_marks
from pynvim_pp.preview import set_preview
from std2.itertools import group_by
from yaml import SafeDumper, add_representer, safe_dump_all
from yaml.nodes import ScalarNode

from ...lang import LANG
from ...registry import rpc
from ...shared.context import EMPTY_CONTEXT
from ...shared.types import Edit, Mark, SnippetEdit
from ...snippets.consts import MOD_PAD
from ...snippets.loaders.neosnippet import load_neosnippet
from ...snippets.parse import parse
from ...snippets.parsers.types import ParseError
from ...snippets.types import LoadError, ParsedSnippet
from ..rt_types import Stack


def _repr(dumper: SafeDumper, data: str) -> ScalarNode:
    node: ScalarNode = dumper.represent_scalar("tag:yaml.org,2002:str", data, style="|")
    return node


add_representer(str, _repr, Dumper=SafeDumper)


def _fmt_yaml(data: Sequence[Any], width: int, indent: int) -> str:
    yaml = safe_dump_all(
        data,
        allow_unicode=True,
        explicit_start=True,
        width=width,
        indent=indent,
    )
    return yaml


def _trans(
    stack: Stack, snippets: Iterable[ParsedSnippet]
) -> Iterator[Tuple[AbstractSet[str], Edit, Sequence[Mark]]]:
    for snippet in snippets:
        edit = SnippetEdit(grammar="lsp", new_text=snippet.content)
        parsed, marks = parse(
            stack.settings.match.unifying_chars,
            context=EMPTY_CONTEXT,
            snippet=edit,
            visual="",
        )
        yield snippet.matches, parsed, marks


def _pprn(
    exts: AbstractSet[str],
    snippets: Iterable[Tuple[AbstractSet[str], Edit, Sequence[Mark]]],
) -> str:
    def cont() -> Iterator[Mapping[str, Any]]:
        mapping = {"extensions": sorted(exts, key=strxfrm)}
        yield mapping
        for matches, edit, marks in snippets:
            mapping = {
                "matches": sorted(matches, key=strxfrm),
                "marks": group_by(
                    marks, key=lambda m: str(m.idx % MOD_PAD), val=lambda m: m.text
                ),
                "expanded": edit.new_text,
            }
            yield mapping

    return _fmt_yaml(tuple(cont()), width=80, indent=2)


@rpc(blocking=True)
def eval_snips(nvim: Nvim, stack: Stack, visual: bool) -> None:
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
    line_count = buf_line_count(nvim, buf=buf)
    path = PurePath(normcase(buf_name(nvim, buf=buf)))

    if visual:
        (lo, _), (hi, _) = operator_marks(nvim, buf=buf, visual_type=None)
        hi = min(line_count, hi + 1)
    else:
        lo, hi = 0, line_count

    lines = buf_get_lines(nvim, buf=buf, lo=lo, hi=hi)

    try:
        _, exts, snips = load_neosnippet(path, lines=enumerate(lines, start=lo + 1))
    except LoadError as e:
        preview: Sequence[str] = str(e).splitlines()
        with hold_win_pos(nvim, win=win):
            set_preview(nvim, syntax="", preview=preview)
        write(nvim, LANG("snip load fail"))

    else:
        try:
            snippets = tuple(_trans(stack, snippets=snips))
        except ParseError as e:
            preview = str(e).splitlines()
            with hold_win_pos(nvim, win=win):
                set_preview(nvim, syntax="", preview=preview)
            write(nvim, LANG("snip parse fail"))
        else:
            preview = _pprn(exts, snippets=snippets).splitlines()
            with hold_win_pos(nvim, win=win):
                set_preview(nvim, syntax="yaml", preview=preview)
            if preview:
                write(nvim, LANG("snip parse succ"))
            else:
                write(nvim, LANG("snip parse empty"))
