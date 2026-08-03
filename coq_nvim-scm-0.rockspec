rockspec_format = "3.0"

package = "coq_nvim"
version = "scm-0"

source = {
  url = "git+https://github.com/ms-jpq/coq_nvim.git",
  branch = "coq",
}

description = {
  homepage = "https://github.com/ms-jpq/coq_nvim",
  license = "MIT",
}

build = {
  type = "builtin",
  copy_directories = {
    "ftdetect",
    "ftplugin",
    "syntax",
  },
}
