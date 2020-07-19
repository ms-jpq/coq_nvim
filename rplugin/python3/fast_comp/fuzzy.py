from collections import deque
from dataclasses import asdict, dataclass
from locale import strxfrm
from math import inf
from typing import Any, Callable, Dict, Iterator, Sequence, Set, Union, cast

from pynvim import Nvim

from .nvim import VimCompletion
from .types import Fuzziness, FuzzyOptions, SourceFeed, Step


@dataclass(frozen=True)
class Payload:
    row: int
    new_col: int
    new_line: str


def fuzziness(prefix: str, normalized: str) -> Fuzziness:
    matches: Set[int] = set()
    idx = 0

    for char in prefix:
        new = normalized.find(char, idx)
        if new != -1:
            matches.add(new)
            idx = new + 1

    rank = (len(matches) * -1, sum(matches))
    full_match = normalized.startswith(prefix)
    return Fuzziness(full_match=full_match, matches=matches, rank=rank)


def rank(step: Step) -> Sequence[Union[float, int, str]]:
    comp = step.comp
    text = strxfrm(comp.sortby or comp.label or comp.text).lower()
    return (*step.fuzz.rank, step.priority * -1, text)


def gen_payload(feed: SourceFeed, text: str) -> Payload:
    line = feed.prefix.line
    row = feed.position.row - 1
    col = feed.position.col
    begin = col - len(feed.prefix.alnums)
    end = col
    new_col = begin + len(text)
    new_line = line[:begin] + text + line[end:]
    return Payload(row=row, new_col=new_col, new_line=new_line)


def context_gen(text: str, fuzz: Fuzziness) -> str:
    match_set = fuzz.matches

    def gen() -> Iterator[str]:
        for idx, char in enumerate(text):
            inclusive = idx in match_set
            if inclusive and (idx - 1) not in match_set:
                yield "["
            yield char
            if inclusive and (idx + 1) not in match_set:
                yield "]"

    return "".join(gen())


def vimify(feed: SourceFeed, step: Step) -> VimCompletion:
    source = f"[{step.source}]"
    comp = step.comp
    menu = f"{comp.kind} {source}" if comp.kind else source
    abbr = (
        (comp.label or comp.text)
        if step.fuzz.full_match
        else context_gen(comp.text, fuzz=step.fuzz)
    )
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

        fuzzy_steps = cache(feed, steps)
        for step in sorted(fuzzy_steps, key=rank):
            source = step.source
            limit = limits.get(source, inf)
            seen_count = seen_by_source.get(source, 0)
            seen_by_source[source] = seen_count + 1
            if seen_count <= limit:

                text = step.comp.text
                matches = len(step.fuzz.matches)
                if (
                    text not in seen
                    and text != prefix
                    and (step.fuzz.full_match or matches >= options.min_match)
                ):
                    seen.add(text)
                    yield vimify(feed, step=step)

    return fuzzy
