from argparse import Namespace
from contextlib import nullcontext
from locale import strxfrm
from os.path import normcase
from pathlib import PurePath
from typing import Any, Iterator, Mapping, Sequence

from pynvim.api.nvim import Nvim
from pynvim_pp.api import (
    buf_commentstr,
    buf_filetype,
    buf_get_lines,
    buf_line_count,
    buf_name,
    chdir,
    cur_buf,
    cur_win,
    get_cwd,
    win_get_buf,
)
from pynvim_pp.hold import hold_win_pos
from pynvim_pp.lib import async_call, awrite, display_width, go, write
from pynvim_pp.logging import log
from pynvim_pp.operators import operator_marks
from pynvim_pp.preview import set_preview
from std2.argparse import ArgparseError, ArgParser
from std2.locale import pathsort_key
from yaml import SafeDumper, add_representer, safe_dump_all
from yaml.nodes import ScalarNode, SequenceNode

from ...consts import REPL_GRAMMAR
from ...lang import LANG
from ...paths.show import fmt_path
from ...registry import rpc
from ...shared.types import SnippetGrammar
from ...snippets.parsers.parser import decode_mark_idx
from ...snippets.parsers.types import ParseError, ParseInfo
from ...snippets.types import LoadError
from ..rt_types import Stack
from .snippets import (
    Compiled,
    compile_one,
    compile_user_snippets,
    snippet_paths,
    user_mtimes,
)

_WIDTH = 80
_TAB = 2


def _repr_str(dumper: SafeDumper, data: str) -> ScalarNode:
    if len(data.splitlines()) > 1:
        style = "|"
    elif display_width(data, tabsize=_TAB) > _WIDTH:
        style = ">"
    else:
        style = ""
    node = dumper.represent_scalar("tag:yaml.org,2002:str", data, style=style)
    return node


def _repr_seq(dumper: SafeDumper, data: Sequence[Any]) -> SequenceNode:
    node = dumper.represent_sequence("tag:yaml.org,2002:seq", data, flow_style=True)
    return node


add_representer(str, _repr_str, Dumper=SafeDumper)
add_representer(list, _repr_seq, Dumper=SafeDumper)


def _fmt_yaml(data: Sequence[Any]) -> str:
    yaml = safe_dump_all(
        data,
        allow_unicode=True,
        explicit_start=True,
        sort_keys=False,
        width=_WIDTH,
        indent=_TAB,
    )
    return str(yaml)


def _pprn(
    compiled: Compiled,
) -> str:
    def cont() -> Iterator[Mapping[str, Any]]:
        sorted_exts = sorted(compiled.exts, key=strxfrm)
        if sorted_exts:
            mapping: Mapping[str, Any] = {"extends": sorted_exts}
            yield mapping

        for parsed, edit, marks in compiled.parsed:
            mapping = {}
            if parsed.label:
                mapping.update(label=parsed.label)

            mapping.update(
                matches=sorted(parsed.matches, key=strxfrm),
                expanded=edit.new_text.expandtabs(_TAB),
            )

            if sorted_marks := tuple(
                [decode_mark_idx(m.idx), m.text]
                for m in sorted(marks, key=lambda m: (m.begin, m.end))
            ):
                mapping.update(marks=sorted_marks)

            yield mapping

    return _fmt_yaml(tuple(cont()))


@rpc(blocking=True)
def eval_snips(
    nvim: Nvim,
    stack: Stack,
    visual: bool,
    maybe_grammar: str = REPL_GRAMMAR,
) -> None:
    try:
        grammar = SnippetGrammar[maybe_grammar]
    except KeyError:
        grammar = SnippetGrammar.lsp
        log.warn("%s", "bad snippet grammar -- reverting to LSP")

    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
    line_count = buf_line_count(nvim, buf=buf)
    path = PurePath(normcase(buf_name(nvim, buf=buf)))
    comment_str = buf_commentstr(nvim, buf=buf)
    clipboard = nvim.funcs.getreg()
    info = ParseInfo(visual="", clipboard=clipboard, comment_str=comment_str)

    if visual:
        (lo, _), (hi, _) = operator_marks(nvim, buf=buf, visual_type=None)
        hi = min(line_count, hi + 1)
    else:
        lo, hi = 0, line_count

    lines = buf_get_lines(nvim, buf=buf, lo=lo, hi=hi)

    try:
        compiled = compile_one(
            stack,
            grammar=grammar,
            path=path,
            info=info,
            lines=enumerate(lines, start=lo + 1),
        )
    except (LoadError, ParseError) as e:
        preview = str(e).splitlines()
        with hold_win_pos(nvim, win=win):
            set_preview(nvim, syntax="", preview=preview)
        write(nvim, LANG("snip parse fail"))

    else:
        preview = _pprn(compiled).splitlines()
        with hold_win_pos(nvim, win=win):
            set_preview(nvim, syntax="yaml", preview=preview)
        if preview:
            write(nvim, LANG("snip parse succ"))
        else:
            write(nvim, LANG("no snippets found"))


def _parse_args(args: Sequence[str], filetype: str) -> Namespace:
    parser = ArgParser()
    sub_parsers = parser.add_subparsers(dest="action", required=True)

    sub_parsers.add_parser("ls")
    sub_parsers.add_parser("cd")
    sub_parsers.add_parser("compile")

    with nullcontext(sub_parsers.add_parser("edit")) as p:
        p.add_argument("filetype", nargs="?", default=filetype)

    return parser.parse_args(args)


@rpc(blocking=True)
def snips(nvim: Nvim, stack: Stack, args: Sequence[str]) -> None:
    buf = cur_buf(nvim)
    ft = buf_filetype(nvim, buf=buf)

    try:
        ns = _parse_args(args, filetype=ft or "*")
    except ArgparseError as e:
        write(nvim, e, error=True)

    else:
        if ns.action == "ls":
            cwd = get_cwd(nvim)

            async def c1() -> None:
                _, mtimes = await user_mtimes(
                    nvim, user_path=stack.settings.clients.snippets.user_path
                )
                preview = tuple(
                    fmt_path(cwd, path=path, is_dir=False)
                    for path in sorted(mtimes, key=pathsort_key)
                )

                def cont() -> None:
                    if mtimes:
                        set_preview(nvim, syntax="", preview=preview)
                    else:
                        write(nvim, LANG("no snippets found"))

                await async_call(nvim, cont)

            go(nvim, aw=c1())

        elif ns.action == "cd":

            async def c2() -> None:
                paths = await snippet_paths(
                    nvim, user_path=stack.settings.clients.snippets.user_path
                )
                if paths:
                    path, *_ = paths
                    path.mkdir(parents=True, exist_ok=True)
                    await async_call(nvim, lambda: chdir(nvim, path))
                else:
                    assert False

            go(nvim, aw=c2())

        elif ns.action == "compile":

            async def c3() -> None:
                await awrite(nvim, LANG("waiting..."))
                try:
                    await compile_user_snippets(nvim, stack=stack)
                except (LoadError, ParseError) as e:
                    preview = str(e).splitlines()

                    def cont() -> None:
                        set_preview(nvim, syntax="", preview=preview)
                        write(nvim, LANG("snip parse fail"))

                    await async_call(nvim, cont)
                else:
                    await awrite(nvim, LANG("snip parse succ"))

            go(nvim, aw=c3())

        elif ns.action == "edit":

            async def c4() -> None:
                paths, mtimes = await user_mtimes(
                    nvim, user_path=stack.settings.clients.snippets.user_path
                )
                path, *_ = paths
                exts = {path.stem: path for path in mtimes}
                snip_path = exts.get(ns.filetype, path / f"{ns.filetype}.snip")
                snip_path.parent.mkdir(parents=True, exist_ok=True)

                def cont() -> None:
                    escaped = nvim.funcs.fnameescape(normcase(snip_path))
                    nvim.feedkeys(f":edit {escaped}", "n", False)

                await async_call(nvim, cont)

            go(nvim, aw=c4())

        else:
            assert False
