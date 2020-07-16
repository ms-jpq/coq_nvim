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
        enabled=config["enabled"],
        priority=config["priority"],
        short_name=config["short_name"],
        timeout=config["timeout"],
        config=config["config"],
        limit=config["limit"] or inf,
    )
    return spec


def initial(user_config: Any) -> Settings:
    config = merge(load_json(settings_json), user_config)
    sources = {name: load_source(conf) for name, conf in config["sources"].items()}
    settings = Settings(sources=sources)
    return settings


def load_factories(settings: Settings) -> Iterator[SourceFactory]:
    for name, spec in settings.sources.items():
        for path in load_hierarchy:
            candidate = join(path, spec.main)
            if exists(candidate):
                mod = load_module(candidate)
                for name, func in getmembers(mod, isfunction):
                    if name == module_entry_point:
                        seed = SourceSeed(config=spec.config)
                        fact = SourceFactory(
                            name=name,
                            short_name=spec.short_name,
                            priority=spec.priority,
                            timeout=spec.timeout,
                            limit=spec.limit,
                            seed=seed,
                            manufacture=func,
                        )
                        yield fact
