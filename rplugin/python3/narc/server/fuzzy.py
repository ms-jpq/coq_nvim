from dataclasses import asdict, dataclass
from itertools import repeat
from locale import strxfrm
from os import linesep
from typing import Any, Callable, Dict, Iterator, Match, Sequence, Set, Union, cast

from ..shared.types import Context
from .match import gen_metric_wrap
from .nvim import VimCompletion
from .types import DisplayOptions, MatchOptions, Metric, Payload, Suggestion


@dataclass(frozen=True)
class Step:
    suggestion: Suggestion
    metric: Metric


def fuzzify(context: Context, suggestion: Suggestion, options: MatchOptions) -> Step:
    metric = gen_metric_wrap(
        context, suggestion=suggestion, options=options, use_secondary=True
    )
    return Step(suggestion=suggestion, metric=metric)


def rank(fuzz: Step) -> Sequence[Union[float, int, str]]:
    suggestion, metric = fuzz.suggestion, fuzz.metric
    text = (
        suggestion.sortby
        or suggestion.label
        or strxfrm(suggestion.match_normalized).lower()
    )
    return (
        metric.prefix_matches * -1,
        metric.num_matches * -1,
        metric.consecutive_matches * -1,
        suggestion.rank * -1,
        metric.density * -1,
        text,
    )


def context_gen(fuzz: Step) -> str:
    match_set = fuzz.metric.matches
    text = fuzz.suggestion.match
    label = fuzz.suggestion.label or text

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


def gen_payload(suggestion: Suggestion) -> Payload:
    return Payload(
        position=suggestion.position,
        medit=suggestion.medit,
        ledits=suggestion.ledits,
        snippet=suggestion.snippet,
    )


def shorten(text: str, tabsize: int, max_width: int, ellipsis: str) -> str:
    def expand_ws() -> Iterator[str]:
        for c in text:
            if c == linesep:
                yield " "
            elif c == "\t":
                yield from repeat(" ", tabsize)
            else:
                yield c

    def cont() -> Iterator[str]:
        for i, c in enumerate(expand_ws(), 1):
            if i < max_width:
                yield c
            else:
                yield ellipsis
                break

    return "".join(cont())


def vimify(fuzz: Step, display: DisplayOptions) -> VimCompletion:
    suggestion, metric = fuzz.suggestion, fuzz.metric
    source = f"[{suggestion.source_shortname}]"
    menu = f"{suggestion.kind} {source}" if suggestion.kind else source
    long_abbr = (
        (suggestion.label or suggestion.match)
        if metric.full_match or not metric.num_matches
        else context_gen(fuzz)
    )
    max_width = display.pum_max_len - len(menu)
    abbr = shorten(
        long_abbr,
        tabsize=display.tabsize,
        max_width=max_width,
        ellipsis=display.ellipsis,
    )
    user_data = gen_payload(suggestion)
    ret = VimCompletion(
        equal=1,
        icase=1,
        dup=1,
        empty=1,
        word="",
        abbr=abbr,
        menu=menu,
        info=suggestion.doc,
        user_data=asdict(user_data),
    )
    return ret


def fuzzy(
    context: Context,
    suggestions: Sequence[Suggestion],
    match_opt: MatchOptions,
    display_opt: DisplayOptions,
    limits: Dict[str, float],
) -> Iterator[VimCompletion]:
    seen: Set[str] = set()
    seen_by_source: Dict[str, int] = {}
    steps = (
        fuzzify(context, suggestion=suggestion, options=match_opt)
        for suggestion in suggestions
    )
    sorted_steps = sorted(steps, key=cast(Callable[[Step], Any], rank))
    for fuzz in sorted_steps:
        suggestion = fuzz.suggestion
        unique, source, text = suggestion.unique, suggestion.source, suggestion.match
        seen_count = seen_by_source.get(source, 0) + 1
        seen_by_source[source] = seen_count

        if seen_count <= limits[source]:
            if not unique or text not in seen:
                if unique:
                    seen.add(text)
                yield vimify(fuzz, display=display_opt)
