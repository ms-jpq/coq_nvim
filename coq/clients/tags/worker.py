from pathlib import Path
from shutil import which
from subprocess import check_call, check_output
from time import sleep
from typing import Iterator, Sequence, Tuple

from pynvim_pp.logging import log

from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import PollingClient
from ...shared.types import Completion, Context, Edit
from .parser import parse


class Worker(BaseWorker[PollingClient, None]):
    def __init__(
        self, supervisor: Supervisor, options: PollingClient, misc: None
    ) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        if which("etags"):
            supervisor.pool.submit(self._poll)

    def _poll(self) -> None:
        try:
            while True:
                sleep(self._options.polling_interval)
        except Exception as e:
            log.exception("%s", e)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        match = context.words or (context.syms if self._options.match_syms else "")

        path = Path(context.filename).resolve()
        if path.exists():
            raw = check_output(("etags", "-o", "-", str(path)), text=True)

            def cont() -> Iterator[Completion]:
                for section in parse(raw, raise_err=False):
                    for tag in section.tags:
                        word = tag.name or tag.text
                        edit = Edit(new_text=word)
                        cmp = Completion(
                            source=self._options.short_name,
                            tie_breaker=self._options.tie_breaker,
                            primary_edit=edit,
                        )
                        yield cmp

            yield tuple(cont())

