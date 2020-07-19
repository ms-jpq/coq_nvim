from dataclasses import asdict, dataclass
from locale import strxfrm
from typing import Any, Callable, Dict, Iterator, Set, Tuple, cast

from pynvim import Nvim

from .nvim import VimCompletion
from .types import Position, SourceFeed, Step


@dataclass(frozen=True)
class Payload:
    row: int
    new_col: int
    new_line: str


def rank(annotated: Step) -> Tuple[float, str]:
    comp = annotated.comp
    text = strxfrm(comp.sortby or comp.label or comp.text).lower()
    return annotated.priority * -1, text


def gen_payload(feed: SourceFeed, text: str) -> Payload:
    row = feed.position.row - 1
    col = feed.position.col
    begin = col - len(feed.prefix)
    end = col
    new_col = begin + len(text)
    new_line = feed.line[:begin] + text + feed.line[end:]
    return Payload(row=row, new_col=new_col, new_line=new_line)


def vimify(feed: SourceFeed, step: Step) -> VimCompletion:
    source = f"[{step.source}]"
    comp = step.comp
    menu = f"{comp.kind} {source}" if comp.kind else source
    abbr = comp.label or comp.text
    user_data = gen_payload(feed, text=comp.text)
    ret = VimCompletion(
        equal=1,
        icase=1,
        dup=1,
        empty=1,
        word="",
        abbr=abbr,
        menu=menu,
        info=comp.doc,
        user_data=asdict(user_data),
    )
    return ret


def fuzzy_criterion(prefix: str, candidate: str) -> bool:
    return prefix.lower() in candidate.lower()


def lru() -> Callable[[Position, Iterator[Step]], Iterator[VimCompletion]]:
    pass


def patch(nvim: Nvim, comp: Dict[str, Any]) -> None:
    data = comp.get("user_data")
    if type(data) == dict:
        try:
            payload = Payload(**cast(dict, data))
        except TypeError:
            pass
        else:
            row = payload.row
            col = payload.new_col
            lines = payload.new_line.splitlines()
            buf = nvim.api.get_current_buf()
            nvim.api.buf_set_lines(buf, row, row + 1, True, lines)
            win = nvim.api.get_current_win()
            nvim.api.win_set_cursor(win, (row + 1, col))


def fuzzer() -> Callable[[SourceFeed, Iterator[Step]], Iterator[VimCompletion]]:
    def fuzzy(feed: SourceFeed, steps: Iterator[Step]) -> Iterator[VimCompletion]:
        prefix = feed.prefix

        seen: Set[str] = set()
        for step in sorted(steps, key=rank):
            text = step.comp.text
            if text not in seen and text != prefix and fuzzy_criterion(prefix, text):
                seen.add(text)
                yield vimify(feed, step=step)

    return fuzzy
