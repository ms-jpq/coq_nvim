from pynvim import Nvim

from ...shared.types import SnippetContext, SnippetSource

NAME = "simple_lsp"


async def main(nvim: Nvim) -> SnippetSource:
    async def apply(context: SnippetContext) -> None:
        pass

    return apply
