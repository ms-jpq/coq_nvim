from dataclasses import asdict, dataclass
from locale import strxfrm
from typing import Any, Callable, Dict, Iterator, Sequence, Set, Union, cast

from pynvim import Nvim

from .nvim import VimCompletion
from .types import FuzzyOptions, SourceFeed, Step


@dataclass(frozen=True)
class Payload:
    row: int
    new_col: int
    new_line: str


@dataclass(frozen=True)
class FuzzyStep:
    step: Step
    non_overlapping: bool
    full_match: bool
    matches: Set[int]
    rank: Sequence[Union[int, str]]


def fuzzify(feed: SourceFeed, step: Step) -> FuzzyStep:
    prefix = feed.prefix.alnums
    text = step.comp.text
    normalized = step.normalized
    matches: Set[int] = set()
    idx = 0

    for char in prefix:
        new = normalized.find(char, idx)
        if new != -1:
            matches.add(new)
            idx = new + 1

    rank = (len(matches) * -1, sum(matches))
    full_match = normalized.startswith(prefix)
    non_overlapping = len(text) > len(prefix) and text != prefix
    return FuzzyStep(
        step=step,
        non_overlapping=non_overlapping,
        full_match=full_match,
        matches=matches,
        rank=rank,
    )


def rank(fuzz: FuzzyStep) -> Sequence[Union[float, int, str]]:
    comp = fuzz.step.comp
    text = strxfrm(comp.sortby or comp.label or comp.text).lower()
    return (*fuzz.rank, fuzz.step.priority * -1, text)


def gen_payload(feed: SourceFeed, text: str) -> Payload:
    line = feed.prefix.line
    row = feed.position.row - 1
    col = feed.position.col
    begin = col - len(feed.prefix.alnums)
    end = col
    new_col = begin + len(text)
    new_line = line[:begin] + text + line[end:]
    return Payload(row=row, new_col=new_col, new_line=new_line)


def context_gen(fuzz: FuzzyStep) -> str:
    match_set = fuzz.matches
    text = fuzz.step.comp.text

    def gen() -> Iterator[str]:
        for idx, char in enumerate(text):
            inclusive = idx in match_set
            if inclusive and (idx - 1) not in match_set:
                yield "["
            yield char
            if inclusive and (idx + 1) not in match_set:
                yield "]"

    label = "".join(gen())
    return f"{text} <- {label}"


def vimify(feed: SourceFeed, fuzz: FuzzyStep) -> VimCompletion:
    step = fuzz.step
    source = f"[{step.source_shortname}]"
    comp = step.comp
    menu = f"{comp.kind} {source}" if comp.kind else source
    abbr = (comp.label or comp.text) if fuzz.full_match else context_gen(fuzz)
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
    options: FuzzyOptions, limits: Dict[str, float]
) -> Callable[[SourceFeed, Iterator[Step]], Iterator[VimCompletion]]:
    def fuzzy(feed: SourceFeed, steps: Iterator[Step]) -> Iterator[VimCompletion]:
        seen: Set[str] = set()
        seen_by_source: Dict[str, int] = {}

        fuzzy_steps = (fuzzify(feed, step=step) for step in steps)
        for fuzz in sorted(fuzzy_steps, key=rank):
            step = fuzz.step
            source = step.source
            seen_count = seen_by_source.get(source, 0) + 1
            seen_by_source[source] = seen_count
            text = step.comp.text
            matches = len(fuzz.matches)

            if (
                seen_count <= limits[source]
                and text not in seen
                and fuzz.non_overlapping
                and (fuzz.full_match or matches >= options.min_match)
            ):
                seen.add(text)
                yield vimify(feed, fuzz=fuzz)

    return fuzzy
