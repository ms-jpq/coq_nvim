from itertools import chain
from locale import strxfrm
from os import linesep
from typing import AbstractSet, Iterator, Mapping, Sequence

from pynvim import Nvim
from pynvim_pp.preview import set_preview
from std2.locale import si_prefixed_smol

from ...databases.insertions.database import Statistics
from ...registry import rpc
from ...shared.parse import display_width
from ..rt_types import Stack

TAB_SIZE = 2
H_SEP = " | "
V_SEP = "-"


def _table(headers: AbstractSet[str], rows: Mapping[str, Mapping[str, str]]) -> str:
    s_headers = sorted(headers, key=strxfrm)
    s_rows = sorted(rows.items(), key=lambda kv: strxfrm(kv[0]))

    c0_just = max(chain((0,), (display_width(k, tabsize=TAB_SIZE) for k, _ in s_rows)))
    c_justs = {
        header: max(
            chain(
                (display_width(header, tabsize=TAB_SIZE),),
                (
                    display_width(vs.get(header, ""), tabsize=TAB_SIZE)
                    for _, vs in s_rows
                ),
            )
        )
        for header in s_headers
    }

    def cont() -> Iterator[str]:
        yield H_SEP.join(
            chain(
                (" " * c0_just,),
                (header.ljust(c_justs[header]) for header in s_headers),
            )
        )
        for k, vs in s_rows:
            yield H_SEP.join(
                chain(
                    (k.ljust(c0_just),),
                    (vs.get(header, "").ljust(c_justs[header]) for header in s_headers),
                )
            )

    h, *t = cont()
    rep = display_width(h, tabsize=TAB_SIZE)
    sep = f"{linesep}{V_SEP * rep}{linesep}"
    return sep.join(chain((h,), t))


def _trans(stat: Statistics) -> Mapping[str, str]:
    return {}


def _pprn(stats: Sequence[Statistics]) -> str:
    if not stats:
        return ""
    else:
        rows = {stat.source: _trans(stat) for stat in stats}
        headers = next(iter(rows.values()), {}).keys()
        table = _table(headers, rows=rows)
        return table


@rpc(blocking=True)
def stats(nvim: Nvim, stack: Stack, *_: str) -> None:
    stats = stack.idb.stats()
    preview = _pprn(stats).splitlines()
    set_preview(nvim, syntax="", preview=preview)

