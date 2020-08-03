from os.path import dirname, join, realpath

__nap__ = dirname(dirname(realpath(__file__)))
__base__ = dirname(dirname(dirname(__nap__)))
__config__ = join(__base__, "config")
__artifacts__ = join(__base__, "artifacts")
__sql__ = join(__nap__, "clients", "sql")

settings_json = join(__config__, "config.json")

module_entry_point = "main"

load_hierarchy = (dirname(__base__),)

conf_var_name = "nap_settings"
conf_var_name_private = "nap_settings_private"
buf_var_name = "buf_nap"
