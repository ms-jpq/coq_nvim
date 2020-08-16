from logging import (
    DEBUG,
    ERROR,
    FATAL,
    INFO,
    WARN,
    FileHandler,
    Formatter,
    Handler,
    LogRecord,
    StreamHandler,
    getLevelName,
)
from typing import Dict

from pynvim import Nvim

from ..shared.consts import __log_file__
from ..shared.logging import log

LOG_FMT = """
--  {name}
level:    {levelname}
time:     {asctime}
module:   {module}
line:     {lineno}
function: {funcName}
message:  |-
{message}
"""

DATE_FMT = "%Y-%m-%d %H:%M:%S"

LEVELS: Dict[str, int] = {
    getLevelName(lv): lv for lv in (DEBUG, INFO, WARN, ERROR, FATAL)
}


def setup(nvim: Nvim, level: str) -> None:
    class NvimHandler(Handler):
        def handle(self, record: LogRecord) -> None:
            msg = self.format(record)
            if record.levelno >= ERROR:
                nvim.async_call(nvim.err_write, msg)
            else:
                nvim.async_call(nvim.out_write, msg)

    log.setLevel(LEVELS.get(level, DEBUG))
    formatter = Formatter(fmt=LOG_FMT, datefmt=DATE_FMT, style="{")
    handlers = (StreamHandler(), FileHandler(filename=__log_file__), NvimHandler())
    for handler in handlers:
        handler.setFormatter(formatter)
        log.addHandler(handler)
