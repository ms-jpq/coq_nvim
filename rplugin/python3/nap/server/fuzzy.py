from dataclasses import asdict, dataclass
from locale import strxfrm
from typing import Any, Callable, Dict, Iterator, Sequence, Set, Union, cast

from ..shared.types import Completion, Context
from .match import Metric, gen_metric
from .nvim import VimCompletion
from .types import MatchOptions, Payload, Step


@dataclass(frozen=True)
class FuzzyStep:
    step: Step
    full_match: bool
    metric: Metric


def fuzzify(context: Context, step: Step, options: MatchOptions) -> FuzzyStep:
    cword = context.alnums
    match, match_normalized = step.text, step.text_normalized

    metric = gen_metric(
        cword,
        match=match,
        match_normalized=match_normalized,
        transpose_band=options.transpose_band,
    )
    full_match = len(metric.matches) == len(match)
    return FuzzyStep(step=step, full_match=full_match, metric=metric)


def rank(fuzz: FuzzyStep) -> Sequence[Union[float, int, str]]:
    metric = fuzz.metric
    step = fuzz.step
    comp = step.comp
    text = comp.sortby or comp.label or strxfrm(step.text_normalized)
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


def fuzzer(
    options: MatchOptions, limits: Dict[str, float]
) -> Callable[[Context, Iterator[Step]], Iterator[VimCompletion]]:
    min_match = options.min_match

    def fuzzy(context: Context, steps: Iterator[Step]) -> Iterator[VimCompletion]:
        seen: Set[str] = set()
        seen_by_source: Dict[str, int] = {}

        fuzzy_steps = (fuzzify(context, step=step, options=options) for step in steps)
        sorted_steps = sorted(fuzzy_steps, key=cast(Callable[[FuzzyStep], Any], rank))
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
