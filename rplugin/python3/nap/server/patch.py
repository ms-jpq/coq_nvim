from typing import Any, Dict, cast

from pynvim import Nvim

from ..shared.nvim import call
from ..shared.patch import replace_lines
from ..shared.types import LEdit, Position, Snippet, SnippetContext, SnippetEngine
from .edit import Payload


async def apply_patch(nvim: Nvim, engine: SnippetEngine, comp: Dict[str, Any]) -> None:
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
        pass
    else:
        if snippet:
            context = SnippetContext(position=position, snippet=snippet)
            await engine(context)
        else:

            def cont() -> None:
                replace_lines(nvim, payload=payload)

            await call(nvim, cont)
