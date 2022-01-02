from enum import Enum, auto
from pathlib import Path
from sys import stderr
from typing import Sequence, Tuple
from webbrowser import open as open_w

from pynvim import Nvim
from pynvim_pp.api import buf_set_lines, buf_set_option, create_buf, win_close
from pynvim_pp.float_win import list_floatwins, open_float_win
from std2.argparse import ArgparseError, ArgParser
from std2.types import never

from ...consts import (
    MD_C_SOURCES,
    MD_COMPLETION,
    MD_CONF,
    MD_DISPLAY,
    MD_FUZZY,
    MD_KEYBIND,
    MD_MISC,
    MD_PREF,
    MD_README,
    MD_SNIPS,
    MD_SOURCES,
    MD_STATS,
    URI_C_SOURCES,
    URI_COMPLETION,
    URI_CONF,
    URI_DISPLAY,
    URI_FUZZY,
    URI_KEYBIND,
    URI_MISC,
    URI_PREF,
    URI_README,
    URI_SNIPS,
    URI_SOURCES,
    URI_STATISTICS,
)
from ...registry import rpc
from ..rt_types import Stack


class _Topics(Enum):
    index = auto()
    config = auto()
    keybind = auto()
    snips = auto()
    fuzzy = auto()
    comp = auto()
    display = auto()
    sources = auto()
    misc = auto()
    stats = auto()
    perf = auto()
    custom_sources = auto()


def _directory(topic: _Topics) -> Tuple[Path, str]:
    if topic is _Topics.index:
        return MD_README, URI_README
    elif topic is _Topics.config:
        return MD_CONF, URI_CONF
    elif topic is _Topics.keybind:
        return MD_KEYBIND, URI_KEYBIND
    elif topic is _Topics.snips:
        return MD_SNIPS, URI_SNIPS
    elif topic is _Topics.fuzzy:
        return MD_FUZZY, URI_FUZZY
    elif topic is _Topics.comp:
        return MD_COMPLETION, URI_COMPLETION
    elif topic is _Topics.display:
        return MD_DISPLAY, URI_DISPLAY
    elif topic is _Topics.sources:
        return MD_SOURCES, URI_SOURCES
    elif topic is _Topics.misc:
        return MD_MISC, URI_MISC
    elif topic is _Topics.stats:
        return MD_STATS, URI_STATISTICS
    elif topic is _Topics.perf:
        return MD_PREF, URI_PREF
    elif topic is _Topics.custom_sources:
        return MD_C_SOURCES, URI_C_SOURCES
    else:
        never(topic)


def _parse_args(args: Sequence[str]) -> Tuple[_Topics, bool]:
    parser = ArgParser()
    parser.add_argument(
        "topic",
        nargs="?",
        choices=tuple(topic.name for topic in _Topics),
        default=_Topics.index.name,
    )
    parser.add_argument("-w", "--web", action="store_true", default=False)
    ns = parser.parse_args(args)
    return _Topics[ns.topic], ns.web


@rpc(blocking=True)
def _help(nvim: Nvim, stack: Stack, args: Sequence[str]) -> None:
    try:
        topic, use_web = _parse_args(args)
    except ArgparseError as e:
        print(e, file=stderr, flush=True)
    else:
        md, uri = _directory(topic)
        web_d = open_w(uri) if use_web else False
        if not web_d:
            for win in list_floatwins(nvim):
                win_close(nvim, win=win)
            lines = md.read_text("UTF-8").splitlines()
            buf = create_buf(
                nvim, listed=False, scratch=True, wipe=True, nofile=True, noswap=True
            )
            buf_set_lines(nvim, buf=buf, lo=0, hi=-1, lines=lines)
            buf_set_option(nvim, buf=buf, key="modifiable", val=False)
            buf_set_option(nvim, buf=buf, key="syntax", val="markdown")
            open_float_win(nvim, margin=0, relsize=0.95, buf=buf, border="rounded")
