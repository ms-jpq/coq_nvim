from pynvim import Nvim

from ...shared.nvim import print
from ...shared.types import SnippetContext, SnippetEngine, SnippetSeed

NAME = "simple_lsp"


async def main(nvim: Nvim, seed: SnippetSeed) -> SnippetEngine:
    async def apply(context: SnippetContext) -> None:
        await print(nvim, context)

    return apply
