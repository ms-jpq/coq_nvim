from dataclasses import dataclass
from typing import Any, Iterable, MutableSequence, Tuple

from pynvim import Nvim
from std2.pickle import new_encoder

from ..shared.runtime import Metric
from .rt_types import Stack


@dataclass(frozen=True)
class VimCompletion:
    user_data: str
    abbr: str
    menu: str
    kind: str = ""
    word: str = ""
    equal: int = 1
    dup: int = 1
    empty: int = 1


_LUA = """
(function(col, items)
  vim.schedule(
    function()
      local legal_modes = {
        ["i"] = true,
        ["ic"] = true,
        ["ix"] = true
      }
      local legal_cmodes = {
        [""] = true,
        ["eval"] = true,
        ["function"] = true,
        ["ctrl_x"] = true
      }
      local mode = vim.api.nvim_get_mode().mode
      local comp_mode = vim.fn.complete_info({"mode"}).mode
      if legal_modes[mode] and legal_cmodes[comp_mode] then
        -- when `#items ~= 0` there is something to show
        -- when `#items == 0` but `comp_mode == "eval"` there is something to close
        if #items ~= 0 or comp_mode == "eval" then
          vim.fn.complete(col, items)
        end
      end
    end
  )
end)(...)
"""

_ENCODER = new_encoder[VimCompletion](VimCompletion)


def complete(
    nvim: Nvim, stack: Stack, col: int, comp: Iterable[Tuple[Metric, VimCompletion]]
) -> None:
    stack.metrics.clear()
    serialized: MutableSequence[Any] = []
    for m, c in comp:
        stack.metrics[m.comp.uid] = m
        s = _ENCODER(c)
        serialized.append(s)

    nvim.api.exec_lua(_LUA, (col + 1, serialized))
