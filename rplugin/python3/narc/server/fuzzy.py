from dataclasses import asdict, dataclass
from locale import strxfrm
from textwrap import shorten
from typing import Any, Callable, Dict, Iterator, Sequence, Set, Union, cast

from ..shared.types import Completion, Context
from .match import gen_metric_wrap
from .nvim import VimCompletion
from .types import DisplayOptions, MatchOptions, Metric, Payload, Step


@dataclass(frozen=True)
class FuzzyStep:
    step: Step
    metric: Metric


def fuzzify(context: Context, step: Step, options: MatchOptions) -> FuzzyStep:
    metric = gen_metric_wrap(context, step=step, options=options, use_secondary=True)
    return FuzzyStep(step=step, metric=metric)


def rank(fuzz: FuzzyStep) -> Sequence[Union[float, int, str]]:
    metric = fuzz.metric
    step = fuzz.step
    comp = step.comp
    text = (comp.sortby or comp.label or strxfrm(step.text_normalized)).lower()
    return (
        metric.prefix_matches * -1,
        metric.num_matches * -1,
        metric.consecutive_matches * -1,
        step.rank * -1,
        metric.density * -1,
        text,
    )


def context_gen(fuzz: FuzzyStep) -> str:
    match_set = fuzz.metric.matches
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
    full_label = f"{label} <- {fuzzy_label}"
    return full_label


def gen_payload(comp: Completion) -> Payload:
    return Payload(
        position=comp.position,
        medit=comp.medit,
        ledits=comp.ledits,
        snippet=comp.snippet,
    )


def vimify(fuzz: FuzzyStep, pum_max_len: int) -> VimCompletion:
    metric = fuzz.metric
    step = fuzz.step
    comp = step.comp
    source = f"[{step.source_shortname}]"
    menu = f"{comp.kind} {source}" if comp.kind else source
    long_abbr = (
        (comp.label or step.text)
        if comp.snippet or metric.full_match or not metric.num_matches
        else context_gen(fuzz)
    )
    max_width = pum_max_len - len(menu)
    abbr = shorten(long_abbr, width=max_width)
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


def fuzzy(
    steps: Iterator[FuzzyStep],
    display: DisplayOptions,
    options: MatchOptions,
    limits: Dict[str, float],
) -> Iterator[VimCompletion]:
    seen: Set[str] = set()
    seen_by_source: Dict[str, int] = {}

    sorted_steps = sorted(steps, key=cast(Callable[[FuzzyStep], Any], rank))
    for fuzz in sorted_steps:
        step = fuzz.step
        unique = step.comp.unique
        source = step.source
        seen_count = seen_by_source.get(source, 0) + 1
        seen_by_source[source] = seen_count
        text = step.text

        if seen_count <= limits[source]:
            if not unique or text not in seen:
                if unique:
                    seen.add(text)
                yield vimify(fuzz, pum_max_len=display.pum_max_len)
