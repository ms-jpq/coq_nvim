from dataclasses import asdict, dataclass
from locale import strxfrm
from typing import Any, Callable, Dict, Iterator, Sequence, Set, Union, cast

from .nvim import VimCompletion
from .types import SourceFeed, FuzzyOptions, Payload, SourceCompletion, Step


@dataclass(frozen=True)
class FuzzyStep:
    step: Step
    full_match: bool
    matches: Dict[int, str]
    rank: Sequence[Union[int, str]]


def normalize(text: str) -> str:
    return text.lower()


def fuzzify(feed: SourceFeed, step: Step) -> FuzzyStep:
    f_alnums = feed.context.alnums
    fn_alnums = feed.context.normalized_alnums
    sn_alnums = step.normalized_alnums
    matches: Dict[int, str] = {}
    idx = 0

    for char, n_char in zip(f_alnums, fn_alnums):
        m_idx = sn_alnums.find(n_char, idx)
        if m_idx != -1:
            matches[m_idx] = char
            idx = m_idx + 1

    rank = (len(matches) * -1, sum(matches))
    full_match = sn_alnums.startswith(fn_alnums)
    return FuzzyStep(step=step, full_match=full_match, matches=matches, rank=rank)


def rank(fuzz: FuzzyStep) -> Sequence[Union[float, int, str]]:
    comp = fuzz.step.comp
    text = comp.sortby or normalize(strxfrm(comp.label or fuzz.step.text))
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
    text = fuzz.step.text
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

            if (
                seen_count <= limits[source]
                and text not in seen
                and (fuzz.full_match or len(fuzz.matches) >= options.min_match)
            ):
                seen.add(text)
                yield vimify(fuzz=fuzz)

    return fuzzy
