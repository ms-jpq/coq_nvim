from .consts import load_hierarchy, settings_json
from .da import load_json
from .types import Settings


def initial() -> Settings:
    config = load_json(settings_json)
    _sources = config["sources"]

    settings = Settings()
    return settings
