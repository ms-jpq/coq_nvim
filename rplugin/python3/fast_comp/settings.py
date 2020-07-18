from inspect import getmembers, isfunction
from math import inf
from os.path import exists, join
from typing import Any, Iterator

from .consts import load_hierarchy, module_entry_point, settings_json
from .da import load_json, load_module, merge
from .types import Settings, SourceFactory, SourceSeed, SourceSpec


def load_source(config: Any) -> SourceSpec:
    spec = SourceSpec(
        main=config["main"],
        short_name=config["short_name"],
        enabled=config["enabled"],
        priority=config.get("priority"),
        limit=config.get("limit"),
        timeout=config.get("timeout"),
        config=config.get("config"),
    )
    return spec


def initial(user_config: Any) -> Settings:
    config = merge(load_json(settings_json), user_config)
    sources = {name: load_source(conf) for name, conf in config["sources"].items()}
    settings = Settings(sources=sources)
    return settings


def load_factories(settings: Settings) -> Iterator[SourceFactory]:
    for src_name, spec in settings.sources.items():
        if spec.enabled:
            for path in load_hierarchy:
                candidate = join(path, spec.main)
                if exists(candidate):
                    mod = load_module(candidate)
                    for name, func in getmembers(mod, isfunction):
                        if name == module_entry_point:
                            limit = spec.limit or inf
                            timeout = (spec.timeout or inf) / 1000
                            seed = SourceSeed(
                                config=spec.config, limit=limit, timeout=timeout
                            )
                            fact = SourceFactory(
                                name=src_name,
                                short_name=spec.short_name,
                                priority=spec.priority or 0,
                                limit=limit,
                                timeout=timeout,
                                seed=seed,
                                manufacture=func,
                            )
                            yield fact
