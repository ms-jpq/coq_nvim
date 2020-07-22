from dataclasses import asdict, dataclass
from math import inf
from typing import Any, Callable, Dict, Iterator, Sequence, Set, Union, cast

from .nvim import VimCompletion
from .types import FuzzyOptions, Payload, SourceCompletion, SourceFeed, Step


@dataclass(frozen=True)
class FuzzyMetric:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int
    front_bias: float
    density: float


@dataclass(frozen=True)
class FuzzyStep:
    step: Step
    full_match: bool
    matches: Dict[int, str]
    metric: FuzzyMetric


def normalize(text: str) -> str:
    return text.lower()


def fuzzify(feed: SourceFeed, step: Step) -> FuzzyStep:
    f_alnums = feed.context.alnums
    f_n_alnums = feed.context.alnums_normalized
    s_n_alnums = step.text_normalized
    matches: Dict[int, str] = {}

    idx = 0
    pm_idx = inf
    prefix_matches = 0
    consecutive_matches = 0
    for char, n_char in zip(f_alnums, f_n_alnums):
        m_idx = s_n_alnums.find(n_char, idx)
        if m_idx != -1:
            if pm_idx == inf:
                prefix_matches += 1
            if pm_idx == m_idx - 1:
                consecutive_matches += 1
            pm_idx = m_idx
            matches[m_idx] = char
            idx = m_idx + 1

    target_len = len(s_n_alnums)
    num_matches = len(matches)
    density = num_matches / target_len
    front_bias = sum(matches) / (target_len * (target_len + 1) / 2)
    full_match = prefix_matches == target_len
    metric = FuzzyMetric(
        prefix_matches=prefix_matches,
        num_matches=num_matches,
        consecutive_matches=consecutive_matches,
        front_bias=front_bias,
        density=density,
    )
    return FuzzyStep(step=step, full_match=full_match, matches=matches, metric=metric)


def rank(fuzz: FuzzyStep) -> Sequence[Union[float, int, str]]:
    metric = fuzz.metric
    return (
        metric.prefix_matches,
        metric.num_matches,
        metric.consecutive_matches,
        metric.front_bias,
        metric.density,
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


def gen_payload(comp: SourceCompletion) -> Payload:
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
    source = f"[{step.source_shortname}]"
    comp = step.comp
    menu = str(fuzz.metric)
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
) -> Callable[[SourceFeed, Iterator[Step]], Iterator[VimCompletion]]:
    min_match = options.min_match

    def fuzzy(feed: SourceFeed, steps: Iterator[Step]) -> Iterator[VimCompletion]:
        seen: Set[str] = set()
        seen_by_source: Dict[str, int] = {}

        fuzzy_steps = (fuzzify(feed, step=step) for step in steps)
        for fuzz in sorted(fuzzy_steps, key=cast(Callable[[FuzzyStep], Any], rank)):
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
