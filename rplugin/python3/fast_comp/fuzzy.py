from locale import strxfrm
from typing import Callable, Iterator, Set, Tuple

from .nvim import VimCompletion
from .types import SourceFeed, Step


def rank(annotated: Step) -> Tuple[float, str]:
    comp = annotated.comp
    text = strxfrm(comp.sortby or comp.label or comp.text).lower()
    return annotated.priority * -1, text


def vimify(prefix_len: int, step: Step) -> VimCompletion:
    source = f"[{step.source}]"
    comp = step.comp
    menu = f"{comp.kind} {source}" if comp.kind else source
    abbr = comp.label or comp.text
    text = comp.text[prefix_len:]
    ret = VimCompletion(
        equal=1,
        icase=1,
        dup=1,
        empty=1,
        word=text,
        abbr=abbr,
        menu=menu,
        info=comp.doc,
    )
    return ret


def fuzzer() -> Callable[[SourceFeed, Iterator[Step]], Iterator[VimCompletion]]:
    def fuzzy(feed: SourceFeed, steps: Iterator[Step]) -> Iterator[VimCompletion]:
        prefix = feed.prefix
        prefix_len = len(feed.prefix)

        seen: Set[str] = set()
        for step in sorted(steps, key=rank):
            text = step.comp.text
            if text not in seen and text.startswith(prefix) and text != prefix:
                seen.add(text)
                yield vimify(prefix_len, step=step)

    return fuzzy
