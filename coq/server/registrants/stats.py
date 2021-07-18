from itertools import chain
from locale import strxfrm
from os import linesep
from typing import Iterator, Mapping, Sequence

from pynvim import Nvim
from pynvim_pp.preview import set_preview
from std2.locale import si_prefixed_smol

from ...databases.insertions.database import Statistics
from ...registry import rpc
from ...shared.parse import display_width
from ..rt_types import Stack

TAB_SIZE = 2
H_SEP = " │ "
V_SEP = "─"


def _table(headers: Sequence[str], rows: Mapping[str, Mapping[str, str]]) -> str:
    s_rows = sorted(rows.keys(), key=strxfrm)
    c0_just = max(chain((0,), (display_width(key, tabsize=TAB_SIZE) for key in s_rows)))
    c_justs = {
        header: max(
            chain(
                (display_width(header, tabsize=TAB_SIZE),),
                (
                    display_width(vs.get(header, ""), tabsize=TAB_SIZE)
                    for vs in rows.values()
                ),
            )
        )
        for header in headers
    }

    def cont() -> Iterator[str]:
        yield H_SEP.join(
            chain(
                (" " * c0_just,), (header.ljust(c_justs[header]) for header in headers)
            )
        )
        for key in s_rows:
            yield H_SEP.join(
                chain(
                    (key.ljust(c0_just),),
                    (
                        rows[key].get(header, "").ljust(c_justs[header])
                        for header in headers
                    ),
                )
            )

    h, *t = cont()
    rep = display_width(h, tabsize=TAB_SIZE)
    sep = f"{linesep}{V_SEP * rep}{linesep}"
    return sep.join(chain((h,), t))


def _trans(stat: Statistics) -> Mapping[str, str]:
    stat.interrupted
    mapping = {
        "Interrupted": str(stat.interrupted),
        "Inserted": str(stat.inserted),
        "Avg Duration": f"{si_prefixed_smol(stat.avg_duration, precision=0)}s",
        "Q0 Duration": f"{si_prefixed_smol(stat.q50_duration, precision=0)}s",
        "Q50 Duration": f"{si_prefixed_smol(stat.q50_duration, precision=0)}s",
        "Q90 Duration": f"{si_prefixed_smol(stat.q90_duration, precision=0)}s",
        "Q100 Duration": f"{si_prefixed_smol(stat.max_duration, precision=0)}s",
        "Avg Items": str(round(stat.avg_items)),
        "Q50 Items": str(stat.q50_items),
        "Q90 Items": str(stat.q90_items),
        "Q100 Items": str(stat.max_items),
    }
    return mapping


def _pprn(stats: Sequence[Statistics]) -> str:
    if not stats:
        return ""
    else:
        rows = {stat.source: _trans(stat) for stat in stats}
        headers = tuple(key for key, _ in next(iter(rows.values()), {}).items())
        table = _table(headers, rows=rows)
        return table


@rpc(blocking=True)
def stats(nvim: Nvim, stack: Stack, *_: str) -> None:
    stats = stack.idb.stats()
    preview = _pprn(stats).splitlines()
    set_preview(nvim, syntax="", preview=preview)

