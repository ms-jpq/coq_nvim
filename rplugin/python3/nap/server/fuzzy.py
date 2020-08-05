from dataclasses import asdict, dataclass
from locale import strxfrm
from typing import Any, Callable, Dict, Iterator, Sequence, Set, Union, cast

from ..shared.match import Metric, gen_metric
from ..shared.types import Completion, Context
from .nvim import VimCompletion
from .types import MatchOptions, Payload, Step


@dataclass(frozen=True)
class FuzzyStep:
    step: Step
    full_match: bool
    metric: Metric


def fuzzify(context: Context, step: Step, options: MatchOptions) -> FuzzyStep:
    cword, ncword = context.alnums, context.alnums_normalized
    match, n_match = step.text, step.text_normalized

    metric = gen_metric(
        cword, ncword=ncword, match=match, n_match=n_match, options=options,
    )
    full_match = metric.num_matches == len(match)
    return FuzzyStep(step=step, full_match=full_match, metric=metric)


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
    return f"{label} <- {fuzzy_label}"


def gen_payload(comp: Completion) -> Payload:
    return Payload(
        position=comp.position,
        old_prefix=comp.old_prefix,
        new_prefix=comp.new_prefix,
        old_suffix=comp.old_suffix,
        new_suffix=comp.new_suffix,
        ledits=comp.ledits,
        snippet=comp.snippet,
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


def fuzzy(
    steps: Iterator[FuzzyStep], options: MatchOptions, limits: Dict[str, float]
) -> Iterator[VimCompletion]:
    seen: Set[str] = set()
    seen_by_source: Dict[str, int] = {}

    sorted_steps = sorted(steps, key=cast(Callable[[FuzzyStep], Any], rank))
    for fuzz in sorted_steps:
        step = fuzz.step
        source = step.source
        seen_count = seen_by_source.get(source, 0) + 1
        seen_by_source[source] = seen_count
        text = step.text

        if seen_count <= limits[source] and text not in seen:
            seen.add(text)
            yield vimify(fuzz=fuzz)
