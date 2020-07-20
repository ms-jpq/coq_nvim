from collections import deque
from dataclasses import asdict, dataclass
from locale import strxfrm
from math import inf
from typing import Any, Callable, Dict, Iterator, Sequence, Set, Union, cast

from pynvim import Nvim

from .nvim import VimCompletion
from .types import FuzzyOptions, SourceFeed, Step


@dataclass(frozen=True)
class Payload:
    row: int
    new_col: int
    new_line: str


@dataclass(frozen=True)
class FuzzyStep:
    step: Step
    full_match: bool
    matches: Set[int]
    rank: Sequence[Union[int, str]]


def fuzzify(feed: SourceFeed, step: Step) -> FuzzyStep:
    prefix = feed.prefix.alnums
    normalized = step.normalized
    matches: Set[int] = set()
    idx = 0

    for char in prefix:
        new = normalized.find(char, idx)
        if new != -1:
            matches.add(new)
            idx = new + 1

    rank = (len(matches) * -1, sum(matches))
    full_match = normalized.startswith(prefix)
    return FuzzyStep(step=step, full_match=full_match, matches=matches, rank=rank)


def rank(fuzz: FuzzyStep) -> Sequence[Union[float, int, str]]:
    comp = fuzz.step.comp
    text = strxfrm(comp.sortby or comp.label or comp.text).lower()
    return (*fuzz.rank, fuzz.step.priority * -1, text)


def gen_payload(feed: SourceFeed, text: str) -> Payload:
    line = feed.prefix.line
    row = feed.position.row - 1
    col = feed.position.col
    begin = col - len(feed.prefix.alnums)
    end = col
    new_col = begin + len(text)
    new_line = line[:begin] + text + line[end:]
    return Payload(row=row, new_col=new_col, new_line=new_line)


def context_gen(fuzz: FuzzyStep) -> str:
    match_set = fuzz.matches
    text = fuzz.step.comp.text

    def gen() -> Iterator[str]:
        for idx, char in enumerate(text):
            inclusive = idx in match_set
            if inclusive and (idx - 1) not in match_set:
                yield "["
            yield char
            if inclusive and (idx + 1) not in match_set:
                yield "]"

    label = "".join(gen())
    return f"{text}, {label}"


def vimify(feed: SourceFeed, fuzz: FuzzyStep) -> VimCompletion:
    step = fuzz.step
    source = f"[{step.source}]"
    comp = step.comp
    menu = f"{comp.kind} {source}" if comp.kind else source
    abbr = (comp.label or comp.text) if fuzz.full_match else context_gen(fuzz)
    user_data = gen_payload(feed, text=comp.text)
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


def make_cache(
    options: FuzzyOptions,
) -> Callable[[SourceFeed, Sequence[Step]], Iterator[Step]]:
    half_band_size = options.band_size // 2
    queue: deque = deque([])
    # buf -> row -> col
    bufs: Dict[str, Dict[int, Dict[int, Sequence[Step]]]] = {}

    def cache(feed: SourceFeed, steps: Sequence[Step]) -> Iterator[Step]:
        position = feed.position
        queue.append((feed.filename, position))

        if len(queue) > options.cache_size:
            bufname, pos = queue.popleft()
            bufs.get(bufname, {}).get(pos.row, {}).pop(pos.col, None)

        rows = bufs.setdefault(feed.filename, {})
        cols = rows.setdefault(position.row, {})
        cols[position.col] = steps

        def cont() -> Iterator[Step]:
            for col in range(
                position.col - half_band_size, position.col + 1 + half_band_size
            ):
                yield from iter(cols.get(col, ()))

        return cont()

    return cache


def patch(nvim: Nvim, comp: Dict[str, Any]) -> None:
    data = comp.get("user_data")
    if type(data) == dict:
        try:
            payload = Payload(**cast(dict, data))
        except TypeError:
            pass
        else:
            row = payload.row
            col = payload.new_col
            lines = payload.new_line.splitlines()
            buf = nvim.api.get_current_buf()
            nvim.api.buf_set_lines(buf, row, row + 1, True, lines)
            win = nvim.api.get_current_win()
            nvim.api.win_set_cursor(win, (row + 1, col))


def fuzzer(
    options: FuzzyOptions, limits: Dict[str, float]
) -> Callable[[SourceFeed, Sequence[Step]], Iterator[VimCompletion]]:
    cache = make_cache(options)

    def fuzzy(feed: SourceFeed, steps: Sequence[Step]) -> Iterator[VimCompletion]:
        prefix = feed.prefix.alnums
        seen: Set[str] = set()
        seen_by_source: Dict[str, int] = {}

        fuzzy_steps = (fuzzify(feed, step=step) for step in cache(feed, steps))
        for fuzz in sorted(fuzzy_steps, key=rank):
            step = fuzz.step
            source = step.source
            limit = limits.get(source, inf)
            seen_count = seen_by_source.get(source, 0)
            seen_by_source[source] = seen_count + 1
            if seen_count <= limit:

                text = step.comp.text
                matches = len(fuzz.matches)
                if (
                    text not in seen
                    and text != prefix
                    and (fuzz.full_match or matches >= options.min_match)
                ):
                    seen.add(text)
                    yield vimify(feed, fuzz=fuzz)

    return fuzzy
