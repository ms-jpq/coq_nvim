from dataclasses import dataclass
from itertools import chain
from os import linesep
from typing import AsyncIterator, Dict, Sequence

from pynvim import Nvim
from pynvim.api.buffer import Buffer

from ..server.match import find_matches
from ..shared.parse import coalesce, normalize, parse_common_affix
from ..shared.types import Comm, Completion, Context, MEdit, Position, Seed, Source
from .pkgs.nvim import call

NAME = "around"


@dataclass(frozen=True)
class Config:
    band_size: int
    min_length: int
    max_length: int


async def buffer_chars(nvim: Nvim, band_size: int, pos: Position) -> Sequence[str]:
    def cont() -> Sequence[str]:
        buffer: Buffer = nvim.api.get_current_buf()
        line_count: int = nvim.api.buf_line_count(buffer)
        min_idx, max_idx = (
            max(0, pos.row - band_size),
            min(line_count, pos.row + band_size + 1),
        )
        lines: Sequence[str] = nvim.api.buf_get_lines(buffer, min_idx, max_idx, True)
        return lines

    lines = await call(nvim, cont)
    chars = tuple(char for line in lines for char in chain(line, linesep))
    return chars


async def main(comm: Comm, seed: Seed) -> Source:
    config = Config(**seed.config)
    band_size = config.band_size
    min_length, max_length, unifying_chars = (
        config.min_length,
        config.max_length,
        seed.match.unifying_chars,
    )

    async def source(context: Context) -> AsyncIterator[Completion]:
        position = context.position
        old_prefix = context.alnums_before
        cword, ncword = context.alnums, context.alnums_normalized

        chars = await buffer_chars(comm.nvim, band_size=band_size, pos=position)
        words: Dict[str, str] = {}
        for word in coalesce(
            chars, max_length=max_length, unifying_chars=unifying_chars
        ):
            if word not in words:
                words[word] = normalize(word)

        for word in find_matches(
            cword,
            ncword=ncword,
            min_match=min_length,
            words=words,
            options=seed.match,
            use_secondary=False,
        ):
            match_normalized = words[word]
            _, old_suffix = parse_common_affix(
                context, match_normalized=match_normalized, use_line=False,
            )
            medit = MEdit(
                old_prefix=old_prefix,
                new_prefix=word,
                old_suffix=old_suffix,
                new_suffix="",
            )
            yield Completion(position=position, medit=medit)

    return source
