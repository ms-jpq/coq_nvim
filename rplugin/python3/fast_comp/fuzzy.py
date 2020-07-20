from dataclasses import asdict, dataclass
from locale import strxfrm
from typing import Any, Callable, Dict, Iterator, Sequence, Set, Union, cast

from pynvim import Nvim

from .nvim import VimCompletion
from .types import FuzzyOptions, SourceFeed, Step, SourceCompletion


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
    matches: Dict[int, str]
    rank: Sequence[Union[int, str]]


def fuzzify(feed: SourceFeed, step: Step) -> FuzzyStep:
    original = feed.prefix.alnums
    normalized_prefix = original.lower()
    text = step.comp.new_prefix
    normalized = step.normalized
    matches: Dict[int, str] = {}
    idx = 0

    for o_char, char in zip(original, normalized_prefix):
        m_idx = normalized.find(char, idx)
        if m_idx != -1:
            matches[m_idx] = o_char
            idx = m_idx + 1

    rank = (len(matches) * -1, sum(matches))
    full_match = normalized.startswith(normalized_prefix)
    non_overlapping = len(text) > len(normalized_prefix) and text != normalized_prefix
    return FuzzyStep(
        step=step,
        non_overlapping=non_overlapping,
        full_match=full_match,
        matches=matches,
        rank=rank,
    )


def rank(fuzz: FuzzyStep) -> Sequence[Union[float, int, str]]:
    comp = fuzz.step.comp
    text = strxfrm(comp.sortby or comp.label or comp.new_prefix).lower()
    return (*fuzz.rank, fuzz.step.priority * -1, text)


def gen_payload(feed: SourceFeed, comp: SourceCompletion) -> Payload:
    text = comp.new_prefix
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
    comp = fuzz.step.comp
    text = comp.new_prefix
    label = comp.label or text

    def gen() -> Iterator[str]:
        for idx, char in enumerate(text):
            inclusive = idx in match_set
            if inclusive and (idx - 1) not in match_set:
                yield "["
            m_char = match_set[idx] if inclusive else char
            yield m_char
            if inclusive and (idx + 1) not in match_set:
                yield "]"

    fuzzy_label = "".join(gen())
    return f"{label} <- {fuzzy_label}"


def vimify(feed: SourceFeed, fuzz: FuzzyStep) -> VimCompletion:
    step = fuzz.step
    source = f"[{step.source_shortname}]"
    comp = step.comp
    menu = f"{comp.kind} {source}" if comp.kind else source
    abbr = (comp.label or comp.new_prefix) if fuzz.full_match else context_gen(fuzz)
    user_data = gen_payload(feed, comp=comp)
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
            text = step.comp.new_prefix
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
