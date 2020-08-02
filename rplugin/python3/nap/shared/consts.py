from os.path import dirname, join, realpath

__nap__ = dirname(dirname(realpath(__file__)))
__base__ = dirname(dirname(dirname(__nap__)))
__config__ = join(__base__, "config")
__sql__ = join(__nap__, "clients", "sql")

settings_json = join(__config__, "config.json")

module_entry_point = "main"

load_hierarchy = (dirname(__base__),)
