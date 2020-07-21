from os.path import dirname, join

__base__ = dirname(dirname(dirname(dirname(__file__))))
__config__ = join(__base__, "config")


settings_json = join(__config__, "config.json")

module_entry_point = "main"

load_hierarchy = (
    join(__base__, "clients"),
    dirname(__base__),
)
