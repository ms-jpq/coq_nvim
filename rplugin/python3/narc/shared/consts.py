from os.path import dirname, join, realpath

__narc__ = dirname(dirname(realpath(__file__)))
__base__ = dirname(dirname(dirname(__narc__)))
__config__ = join(__base__, "config")
__artifacts__ = join(__base__, "artifacts")
__log_file__ = join(__base__, "logs", "narc.log")

settings_json = join(__config__, "config.json")

module_entry_point = "main"

load_hierarchy = (dirname(__base__),)

conf_var_name = "narc_settings"
conf_var_name_private = "narc_settings_private"
buf_var_name = "buflocal_narc"
