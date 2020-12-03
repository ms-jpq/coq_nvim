from math import inf
from typing import Any, Mapping, Sequence

from ...shared.consts import settings_json
from ...shared.da import load_json, merge_all
from ..types import (
    DisplayOptions,
    MatchOptions,
    Settings,
    SnippetEngineSpec,
    SourceSpec,
)


def load_source(config: Mapping[str, Any]) -> SourceSpec:
    spec = SourceSpec(
        main=config["main"],
        enabled=config["enabled"],
        short_name=config["short_name"],
        limit=config["limit"],
        unique=config["unique"],
        rank=config["rank"],
        config=config["config"],
    )
    return spec


def load_snippet_engine(config: Mapping[str, Any]) -> SnippetEngineSpec:
    spec = SnippetEngineSpec(
        main=config["main"],
        enabled=config["enabled"],
        kinds=config["kinds"],
        config=config.get("config") or {},
    )
    return spec


def load(configs: Sequence[Any]) -> Settings:
    config = merge_all(load_json(settings_json), *configs, replace=True)
    display_o = config["display"]
    match_o = config["match"]
    display = DisplayOptions(
        ellipsis=display_o["ellipsis"],
        tabsize=display_o["tabsize"],
        pum_max_len=display_o["pum_max_len"],
    )
    match = MatchOptions(
        transpose_band=match_o["transpose_band"],
        unifying_chars={*match_o["unifying_chars"]},
    )
    sources = {name: load_source(conf) for name, conf in config["sources"].items()}
    snippet_engines = {
        name: load_snippet_engine(conf)
        for name, conf in config["snippet_engines"].items()
    }
    settings = Settings(
        retries=config["retries"],
        timeout=(config["timeout"] or inf) / 1000,
        display=display,
        match=match,
        sources=sources,
        snippet_engines=snippet_engines,
        logging_level=config["logging_level"],
    )
    return settings
