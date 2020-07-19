from dataclasses import asdict, dataclass
from locale import strxfrm
from typing import Any, Callable, Dict, Iterator, List, Sequence, Set, Union, cast

from pynvim import Nvim

from .nvim import VimCompletion
from .types import Fuzziness, Position, Settings, SourceFeed, Step


@dataclass(frozen=True)
class Payload:
    row: int
    new_col: int
    new_line: str


def fuzziness(prefix: str, normalized: str) -> Fuzziness:
    matches: List[int] = []
    idx = 0

    for char in prefix:
        new = normalized.find(char, idx)
        if new != -1:
            idx = new + 1
            matches.append(idx)

    rank = (len(matches) * -1, sum(matches))
    return Fuzziness(matches=matches, rank=rank)


def rank(step: Step) -> Sequence[Union[float, int, str]]:
    comp = step.comp
    text = strxfrm(comp.sortby or comp.label or comp.text).lower()
    return (*step.fuzz.rank, step.priority * -1, text)


def gen_payload(feed: SourceFeed, text: str) -> Payload:
    row = feed.position.row - 1
    col = feed.position.col
    begin = col - len(feed.prefix)
    end = col
    new_col = begin + len(text)
    new_line = feed.line[:begin] + text + feed.line[end:]
    return Payload(row=row, new_col=new_col, new_line=new_line)


def context_gen(text: str, fuzz: Fuzziness) -> str:
    match_set = {*fuzz.matches}

    def gen() -> Iterator[str]:
        for idx, char in enumerate(text):
            inclusive = idx in match_set
            if inclusive and (idx - 1) not in match_set:
                yield "["
            yield char
            if inclusive and (idx + 1) not in match_set:
                yield "]"

    return "".join(gen())


def vimify(feed: SourceFeed, step: Step) -> VimCompletion:
    source = f"[{step.source}]"
    comp = step.comp
    menu = f"{comp.kind} {source}" if comp.kind else source
    abbr = (
        (comp.label or comp.text)
        if len(step.fuzz.matches) == len(feed.prefix)
        else context_gen(comp.text, step.fuzz)
    )
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


def fuzzer(
    settings: Settings,
) -> Callable[[SourceFeed, Iterator[Step]], Iterator[VimCompletion]]:
    min_matches = settings.fuzzy.min_match

    def fuzzy(feed: SourceFeed, steps: Iterator[Step]) -> Iterator[VimCompletion]:
        prefix = feed.prefix
        seen: Set[str] = set()

        for step in sorted(steps, key=rank):
            text = step.comp.text
            matches = len(step.fuzz.matches)
            if (
                text not in seen
                and text != prefix
                and (matches >= len(prefix) or matches >= min_matches)
            ):
                seen.add(text)
                yield vimify(feed, step=step)

    return fuzzy
