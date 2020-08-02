from pynvim import Nvim

from ...shared.types import SnippetContext, SnippetEngine

NAME = "simple_lsp"


async def main(nvim: Nvim) -> SnippetEngine:
    async def apply(context: SnippetContext) -> None:
        pass

    return apply
