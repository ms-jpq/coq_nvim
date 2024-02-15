from pathlib import Path, PurePath
from shutil import which
from typing import Any, Iterator, Mapping, cast

from pynvim_pp.lib import decode
from pynvim_pp.nvim import Nvim
from pynvim_pp.types import NoneType
from std2.configparser import hydrate
from std2.graphlib import merge
from std2.pickle.decoder import new_decoder
from yaml import safe_load

from ..clients.buffers.db.database import BDB
from ..clients.buffers.worker import Worker as BuffersWorker
from ..clients.lsp.worker import Worker as LspWorker
from ..clients.paths.worker import Worker as PathsWorker
from ..clients.registers.db.database import RDB
from ..clients.registers.worker import Worker as RegistersWorker
from ..clients.snippet.db.database import SDB
from ..clients.snippet.worker import Worker as SnippetWorker
from ..clients.t9.worker import Worker as T9Worker
from ..clients.tags.db.database import CTDB
from ..clients.tags.worker import Worker as TagsWorker
from ..clients.third_party.worker import Worker as ThirdPartyWorker
from ..clients.tmux.db.database import TMDB
from ..clients.tmux.worker import Worker as TmuxWorker
from ..clients.tree_sitter.db.database import TDB
from ..clients.tree_sitter.worker import Worker as TreeWorker
from ..consts import CONFIG_YML, SETTINGS_VAR, VARS
from ..databases.insertions.database import IDB
from ..shared.lru import LRU
from ..shared.runtime import Supervisor, Worker
from ..shared.settings import LSPClient, Settings
from .reviewer import Reviewer
from .rt_types import Stack, ValidationError
from .state import state


async def _settings() -> Settings:
    yml = safe_load(decode(CONFIG_YML.read_bytes()))
    user_config = cast(Any, (await Nvim.vars.get(NoneType, SETTINGS_VAR)) or {})
    u_conf = hydrate(user_config)

    if isinstance(u_conf, Mapping):
        if isinstance(display := u_conf.get("display"), Mapping):
            if isinstance(icons := display.get("icons"), Mapping):
                yml_icons = yml["display"]["icons"]
                if (aliases := icons.get("aliases")) is not None:
                    yml_icons["aliases"] = aliases
                if (mappings := icons.get("mappings")) is not None:
                    yml_icons["mappings"] = mappings

    merged = merge(yml, u_conf, replace=True)
    config = new_decoder[Settings](Settings)(merged)

    if config.match.max_results <= 0:
        raise ValidationError("match.max_results <= 0")

    return config


def _from_each_according_to_their_ability(
    settings: Settings,
    vars_dir: Path,
    cwd: PurePath,
    supervisor: Supervisor,
) -> Iterator[Worker]:
    clients = settings.clients

    if clients.buffers.enabled:
        bdb = BDB(
            settings.limits.tokenization_limit,
            unifying_chars=settings.match.unifying_chars,
            include_syms=settings.clients.buffers.match_syms,
        )
        yield BuffersWorker.init(supervisor, options=clients.buffers, misc=bdb)

    if clients.paths.enabled:
        yield PathsWorker.init(supervisor, options=clients.paths, misc=None)

    if clients.tree_sitter.enabled:
        tdb = TDB()
        yield TreeWorker.init(supervisor, options=clients.tree_sitter, misc=tdb)

    if clients.lsp.enabled:
        yield LspWorker.init(supervisor, options=clients.lsp, misc=None)

    if clients.registers.enabled:
        rdb = RDB(
            settings.limits.tokenization_limit,
            unifying_chars=settings.match.unifying_chars,
            include_syms=settings.clients.buffers.match_syms,
        )
        yield RegistersWorker.init(supervisor, options=clients.registers, misc=rdb)

    if clients.third_party.enabled:
        yield ThirdPartyWorker.init(
            supervisor, options=cast(LSPClient, clients.third_party), misc=None
        )

    if clients.snippets.enabled:
        sdb = SDB(vars_dir)
        yield SnippetWorker.init(supervisor, options=clients.snippets, misc=sdb)

    if clients.tags.enabled and (ctags := which("ctags")):
        ctdb = CTDB(vars_dir, cwd=cwd)
        yield TagsWorker.init(
            supervisor, options=clients.tags, misc=cast(CTDB, (Path(ctags), ctdb))
        )

    if clients.tmux.enabled and (tmux := which("tmux")):
        tmdb = TMDB(
            settings.limits.tokenization_limit,
            unifying_chars=settings.match.unifying_chars,
            include_syms=settings.clients.buffers.match_syms,
        )
        yield TmuxWorker.init(
            supervisor, options=clients.tmux, misc=cast(TMDB, (Path(tmux), tmdb))
        )

    if clients.tabnine.enabled:
        yield T9Worker.init(supervisor, options=clients.tabnine, misc=None)


async def stack() -> Stack:
    settings = await _settings()
    pum_width = await Nvim.opts.get(int, "pumwidth")
    vars_dir = (
        Path(await Nvim.fn.stdpath(str, "cache")) / "coq" if settings.xdg else VARS
    )
    s = state(cwd=await Nvim.getcwd(), pum_width=pum_width)
    idb = IDB()
    reviewer = Reviewer(
        icons=settings.display.icons,
        options=settings.match,
        db=idb,
    )
    supervisor = Supervisor(
        vars_dir=vars_dir,
        display=settings.display,
        match=settings.match,
        comp=settings.completion,
        limits=settings.limits,
        reviewer=reviewer,
    )
    workers = {
        *_from_each_according_to_their_ability(
            settings,
            vars_dir=vars_dir,
            cwd=s.cwd,
            supervisor=supervisor,
        )
    }
    stack = Stack(
        settings=settings,
        lru=LRU(size=settings.match.max_results),
        metrics={},
        idb=idb,
        supervisor=supervisor,
        workers=workers,
    )
    return stack
