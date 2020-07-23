from dataclasses import asdict, dataclass
from math import inf
from typing import Any, Callable, Dict, Iterator, Sequence, Set, Union, cast

from .nvim import VimCompletion
from .types import Context, FuzzyOptions, Payload, Completion, Step


@dataclass(frozen=True)
class FuzzyMetric:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int
    density: float


@dataclass(frozen=True)
class FuzzyStep:
    step: Step
    full_match: bool
    matches: Dict[int, str]
    metric: FuzzyMetric


def normalize(text: str) -> str:
    return text.lower()


def fuzzify(context: Context, step: Step) -> FuzzyStep:
    c_alnums = context.alnums
    s_alnums = step.text
    s_n_alnums = step.text_normalized
    matches: Dict[int, str] = {}

    idx = 0
    prefix_broken = False
    pm_idx = inf
    prefix_matches = 0
    consecutive_matches = 0
    for i, char in enumerate(c_alnums):
        m_idx = (s_alnums if char.isupper() else s_n_alnums).find(char, idx)
        if m_idx != -1:
            if pm_idx == m_idx - 1:
                consecutive_matches += 1
            pm_idx = m_idx
            matches[m_idx] = char
            idx = m_idx + 1
        if m_idx != i:
            prefix_broken = True
        if not prefix_broken:
            prefix_matches += 1

    num_matches = len(matches)
    full_match = prefix_matches == len(c_alnums)
    density = num_matches / len(s_n_alnums)
    metric = FuzzyMetric(
        prefix_matches=prefix_matches,
        num_matches=num_matches,
        consecutive_matches=consecutive_matches,
        density=density,
    )
    return FuzzyStep(step=step, full_match=full_match, matches=matches, metric=metric)


def rank(fuzz: FuzzyStep) -> Sequence[Union[float, int, str]]:
    metric = fuzz.metric
    return (
        metric.prefix_matches,
        metric.num_matches,
        metric.consecutive_matches,
        metric.density,
        fuzz.step.text_normalized,
    )


def context_gen(fuzz: FuzzyStep) -> str:
    match_set = fuzz.matches
    text = fuzz.step.text
    label = fuzz.step.comp.label or text

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


def gen_payload(comp: Completion) -> Payload:
    return Payload(
        row=comp.position.row,
        col=comp.position.col,
        old_prefix=comp.old_prefix,
        new_prefix=comp.new_prefix,
        old_suffix=comp.old_suffix,
        new_suffix=comp.new_suffix,
    )


def vimify(fuzz: FuzzyStep) -> VimCompletion:
    step = fuzz.step
    comp = step.comp
    source = f"[{step.source_shortname}]"
    menu = f"{comp.kind} {source}" if comp.kind else source
    abbr = (
        (comp.label or (comp.new_prefix + comp.new_suffix))
        if fuzz.full_match
        else context_gen(fuzz)
    )
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


def fuzzer(
    options: FuzzyOptions, limits: Dict[str, float]
) -> Callable[[Context, Iterator[Step]], Iterator[VimCompletion]]:
    min_match = options.min_match

    def fuzzy(context: Context, steps: Iterator[Step]) -> Iterator[VimCompletion]:
        seen: Set[str] = set()
        seen_by_source: Dict[str, int] = {}

        fuzzy_steps = (fuzzify(context, step=step) for step in steps)
        sorted_steps = sorted(
            fuzzy_steps, key=cast(Callable[[FuzzyStep], Any], rank), reverse=True
        )
        for fuzz in sorted_steps:
            step = fuzz.step
            source = step.source
            seen_count = seen_by_source.get(source, 0) + 1
            seen_by_source[source] = seen_count
            text = step.text
            num_matches = fuzz.metric.num_matches

            if (
                seen_count <= limits[source]
                and text not in seen
                and (fuzz.full_match or num_matches >= min_match)
            ):
                seen.add(text)
                yield vimify(fuzz=fuzz)

    return fuzzy
