from dataclasses import asdict, dataclass
from locale import strxfrm
from typing import Any, Callable, Dict, Iterator, Sequence, Set, Union, cast
from os import linesep
from pynvim import Nvim

from .nvim import VimCompletion
from .types import FuzzyOptions, Step, SourceCompletion


@dataclass(frozen=True)
class Payload:
    row: int
    col: int
    old_prefix: str
    new_prefix: str
    old_suffix: str
    new_suffix: str


@dataclass(frozen=True)
class FuzzyStep:
    step: Step
    non_overlapping: bool
    full_match: bool
    matches: Dict[int, str]
    rank: Sequence[Union[int, str]]


def fuzzify(step: Step) -> FuzzyStep:
    original = step.comp.old_prefix
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


def gen_payload(comp: SourceCompletion) -> Payload:
    return Payload(
        row=comp.position.row,
        col=comp.position.col,
        old_prefix=comp.old_prefix,
        new_prefix=comp.new_prefix,
        old_suffix=comp.old_suffix,
        new_suffix=comp.new_suffix,
    )


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


def vimify(fuzz: FuzzyStep) -> VimCompletion:
    step = fuzz.step
    source = f"[{step.source_shortname}]"
    comp = step.comp
    menu = f"{comp.kind} {source}" if comp.kind else source
    abbr = (comp.label or comp.new_prefix) if fuzz.full_match else context_gen(fuzz)
    user_data = gen_payload(comp=comp)
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
            col = payload.col
            old_prefix = payload.old_prefix
            new_prefix = payload.new_prefix
            old_suffix = payload.old_suffix
            new_suffix = payload.new_suffix

            btm_idx = row - (old_prefix.count(linesep) - 1)
            top_idx = row + (old_suffix.count(linesep) - 1) + 1

            buf = nvim.api.get_current_buf()
            old_lines: Sequence[str] = nvim.api.buf_get_lines(
                buf, btm_idx, top_idx, True
            )

            def seek() -> int:
                i = 0
                for r, line in enumerate(old_lines, btm_idx):
                    for c, _ in enumerate(line, 0):
                        if r == row and c == col:
                            return i
                        else:
                            i += 1
                return i

            idx = seek()
            old = "".join(old_lines)
            pre = old[:idx - len(new_prefix)]
            post = old[idx + len(new_suffix) + 1:]
            new_lines = (pre + new_prefix + new_suffix + post).splitlines()

            nvim.api.buf_set_lines(buf, btm_idx, top_idx, True, new_lines)
            win = nvim.api.get_current_win()
            # nvim.api.win_set_cursor(win, (row + 1, col))


def fuzzer(
    options: FuzzyOptions, limits: Dict[str, float]
) -> Callable[[Iterator[Step]], Iterator[VimCompletion]]:
    def fuzzy(steps: Iterator[Step]) -> Iterator[VimCompletion]:
        seen: Set[str] = set()
        seen_by_source: Dict[str, int] = {}

        fuzzy_steps = (fuzzify(step=step) for step in steps)
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
                yield vimify(fuzz=fuzz)

    return fuzzy
