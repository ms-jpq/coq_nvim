from pynvim import Nvim

from ...server.context import gen_context
from ...server.edit import replace_lines
from ...server.types import Payload
from ...shared.nvim import call
from ...shared.parse import parse_common_affix
from ...shared.types import SnippetContext, SnippetEngine, SnippetSeed
from .parse import parse_snippet

NAME = "simple_lsp"


async def main(nvim: Nvim, seed: SnippetSeed) -> SnippetEngine:
    async def apply(context: SnippetContext) -> None:
        ctx, _ = await gen_context(nvim, options=seed.match)
        new_prefix, new_suffix = parse_snippet(ctx, context.snippet.content)
        match_normalized = new_prefix + new_suffix
        old_prefix, old_suffix = parse_common_affix(
            ctx, match_normalized=match_normalized, use_line=True
        )
        payload = Payload(
            position=context.position,
            old_prefix=old_prefix,
            new_prefix=new_prefix,
            old_suffix=old_suffix,
            new_suffix=new_suffix,
            ledits=(),
            snippet=None,
        )

        def cont() -> None:
            replace_lines(nvim, payload=payload)

        await call(nvim, cont)

    return apply
