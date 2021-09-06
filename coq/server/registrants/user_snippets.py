from argparse import Namespace
from locale import strxfrm
from os.path import normcase
from pathlib import PurePath
from typing import Any, Iterator, Mapping, Sequence

from pynvim.api.nvim import Nvim
from pynvim_pp.api import (
    buf_get_lines,
    buf_line_count,
    buf_name,
    cur_win,
    get_cwd,
    win_get_buf,
)
from pynvim_pp.hold import hold_win_pos
from pynvim_pp.lib import async_call, awrite, display_width, go, write
from pynvim_pp.operators import operator_marks
from pynvim_pp.preview import set_preview
from std2.argparse import ArgparseError, ArgParser
from std2.locale import pathsort_key
from yaml import SafeDumper, add_representer, safe_dump_all
from yaml.nodes import ScalarNode, SequenceNode

from ...lang import LANG
from ...paths.show import fmt_path
from ...registry import rpc
from ...snippets.consts import MOD_PAD
from ...snippets.parsers.types import ParseError
from ...snippets.types import LoadError
from ..rt_types import Stack
from .snippets import Compiled, compile_one, compile_user_snippets, user_mtimes

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
            sorted_marks = [
                [str(m.idx % MOD_PAD), m.text]
                for m in sorted(marks, key=lambda m: (m.begin, m.end))
            ]
            mapping = {}
            if parsed.label:
                mapping.update(label=parsed.label)
            mapping.update(
                matches=sorted(parsed.matches, key=strxfrm),
                expanded=edit.new_text.expandtabs(_TAB),
            )
            if sorted_marks:
                mapping.update(marks=sorted_marks)
            yield mapping

    return _fmt_yaml(tuple(cont()))


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
        compiled = compile_one(stack, path=path, lines=enumerate(lines, start=lo + 1))
    except (LoadError, ParseError) as e:
        preview: Sequence[str] = str(e).splitlines()
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


def _parse_args(args: Sequence[str]) -> Namespace:
    parser = ArgParser()
    sub_parsers = parser.add_subparsers(dest="action", required=True)
    sub_parsers.add_parser("compile")
    sub_parsers.add_parser("ls")
    p = sub_parsers.add_parser("edit")
    p.add_argument("filetype")
    return parser.parse_args(args)


@rpc(blocking=True)
def snips(nvim: Nvim, stack: Stack, args: Sequence[str]) -> None:
    try:
        ns = _parse_args(args)
    except ArgparseError as e:
        write(nvim, e, error=True)

    else:
        if ns.action == "compile":

            async def c0() -> None:
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

            go(nvim, aw=c0())

        elif ns.action == "ls":
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

        elif ns.action == "edit":

            async def c2() -> None:
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

            go(nvim, aw=c2())

        else:
            assert False
