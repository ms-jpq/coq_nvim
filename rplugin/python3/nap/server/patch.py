from typing import Any, Callable, Dict, cast

from pynvim import Nvim
from pynvim.api.window import Window

from ..shared.nvim import call
from ..shared.types import LEdit, Position, Snippet, SnippetContext, SnippetEngine
from .edit import replace_lines
from .types import Payload


async def apply_patch(
    nvim: Nvim,
    engine: SnippetEngine,
    engine_available: Callable[[Snippet], bool],
    comp: Dict[str, Any],
) -> bool:
    data = comp.get("user_data")
    d = cast(dict, data)

    try:
        position = Position(**d["position"])
        edits = tuple(
            LEdit(
                begin=Position(row=edit["begin"]["row"], col=edit["begin"]["col"]),
                end=Position(row=edit["end"]["row"], col=edit["end"]["col"]),
                new_text=edit["new_text"],
            )
            for edit in d["ledits"]
        )
        snip = d.get("snippet")
        snippet = Snippet(**snip) if snip else None
        payload = Payload(
            **{**d, **dict(position=position, ledits=edits, snippet=snippet)}
        )
    except (KeyError, TypeError):
        return False
    else:

        def gogo() -> bool:
            prow, pcol = payload.position.row, payload.position.col
            win: Window = nvim.api.get_current_win()
            row, col = nvim.api.win_get_cursor(win)
            if row == prow + 1 and col == pcol:
                return True
            else:
                return False

        go = await call(nvim, gogo)
        if go:
            if snippet and engine_available(snippet):
                context = SnippetContext(position=position, snippet=snippet)
                await engine(context)
            else:

                def cont() -> None:
                    replace_lines(nvim, payload=payload)

                await call(nvim, cont)
            return True
        else:
            return False
