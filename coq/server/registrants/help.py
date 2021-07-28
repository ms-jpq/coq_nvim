from enum import Enum, auto
from pathlib import Path
from typing import Sequence, Tuple
from webbrowser import open as open_w

from pynvim import Nvim
from pynvim_pp.api import buf_set_lines, buf_set_option, create_buf, win_close
from pynvim_pp.float_win import list_floatwins, open_float_win
from pynvim_pp.lib import write
from std2.argparse import ArgparseError, ArgParser
from std2.types import never

from ...consts import (
    MD_CONF,
    MD_KEYBIND,
    MD_PREF,
    MD_README,
    MD_STATISTICS,
    URI_CONF,
    URI_KEYBIND,
    URI_PREF,
    URI_README,
    URI_STATISTICS,
)
from ...registry import rpc
from ..rt_types import Stack


class _Topics(Enum):
    index = auto()
    config = auto()
    keybind = auto()
    stats = auto()
    performance = auto()


def _directory(topic: _Topics) -> Tuple[Path, str]:
    if topic is _Topics.index:
        return MD_README, URI_README
    elif topic is _Topics.config:
        return MD_CONF, URI_CONF
    elif topic is _Topics.keybind:
        return MD_KEYBIND, URI_KEYBIND
    elif topic is _Topics.stats:
        return MD_STATISTICS, URI_STATISTICS
    elif topic is _Topics.performance:
        return MD_PREF, URI_PREF
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
        write(nvim, e, error=True)
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
            open_float_win(nvim, margin=0, relsize=0.95, buf=buf)
