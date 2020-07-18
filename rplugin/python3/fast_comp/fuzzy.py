from locale import strxfrm
from typing import Callable, Iterator, Set, Tuple

from .nvim import VimCompletion
from .types import SourceFeed, Step


def rank(annotated: Step) -> Tuple[float, str]:
    comp = annotated.comp
    text = strxfrm(comp.sortby or comp.label or comp.text).lower()
    return annotated.priority * -1, text


def vimify(feed: SourceFeed, annotated: Step) -> VimCompletion:
    source = f"[{annotated.source}]"
    comp = annotated.comp
    menu = f"{comp.kind} {source}" if comp.kind else source
    pl = len(feed.prefix)
    text = comp.text[pl:]
    ret = VimCompletion(
        equal=1,
        icase=1,
        dup=1,
        empty=1,
        word=text,
        abbr=comp.label,
        menu=menu,
        info=comp.doc,
    )
    return ret


def fuzzer() -> Callable[[SourceFeed, Iterator[Step]], Iterator[VimCompletion]]:
    acc: Set[str] = set()

    def fuzzy(feed: SourceFeed, steps: Iterator[Step]) -> Iterator[VimCompletion]:
        prefix = feed.prefix
        for step in steps:
            ret = vimify(feed, step)
            if ret.word not in acc:
                acc.add(ret.word)
                if ret.word != prefix:
                    yield ret

    return fuzzy
