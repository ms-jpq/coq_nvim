from os.path import dirname, join, realpath

__base__ = dirname(dirname(dirname(dirname(dirname(realpath(__file__))))))
__config__ = join(__base__, "config")


settings_json = join(__config__, "config.json")

module_entry_point = "main"

load_hierarchy = (dirname(__base__),)
