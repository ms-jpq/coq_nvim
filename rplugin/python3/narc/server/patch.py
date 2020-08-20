from typing import Any, Callable, Dict, cast

from pynvim import Nvim
from pynvim.api.window import Window

from ..shared.logging import log
from ..shared.nvim import call
from ..shared.types import (
    LEdit,
    MEdit,
    Position,
    SEdit,
    Snippet,
    SnippetContext,
    SnippetEngine,
)
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
        se = d.get("sedit")
        sedit = SEdit(**se) if se else None
        me = d.get("medit")
        medit = MEdit(**me) if me else None
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
            **{
                **d,
                **dict(
                    position=position,
                    sedit=sedit,
                    medit=medit,
                    ledits=edits,
                    snippet=snippet,
                ),
            }
        )
    except (KeyError, TypeError):
        return False
    else:

        def gogo() -> bool:
            prow, pcol = payload.position.row, payload.position.col
            win: Window = nvim.api.get_current_win()
            row, col = nvim.api.win_get_cursor(win)
            if prow + 1 == row and pcol == col:
                return True
            else:
                return False

        go = await call(nvim, gogo)
        if go:
            if snippet and engine_available(snippet):
                context = SnippetContext(position=position, snippet=snippet)
                await engine(context)
                return True

            elif payload.medit or payload.sedit or payload.ledits:

                def cont() -> None:
                    replace_lines(nvim, payload=payload)

                await call(nvim, cont)
                return True

            else:
                msg = f"Invaild payload: {payload}"
                log.error("%s", msg)
                return False
        else:
            return False
