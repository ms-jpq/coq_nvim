# Docs

Use `:COQhelp` to open up a list of help pages!

Help docs are written in `markdown`.

Use `:COQhelp -w` or `:COQhelp --web` to open help pages in a browser window if possible.

Use `:COQhelp {topic}` or `:COQhelp {topic} --web` to visit a particular topic for more information

- [:COQhelp config](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/CONF.md)

- [:COQhelp keybind](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/KEYBIND.md)

- [:COQhelp snips](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/SNIPS.md)

- [:COQhelp fuzzy](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/FUZZY.md)

- [:COQhelp display](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/DISPLAY.md)

- [:COQhelp sources](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/SOURCES.md)

- [:COQhelp misc](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/MISC.md)

- [:COQhelp perf](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/PERF.md)

- [:COQhelp stats](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/STATS.md)

---

## Commands

### `COQnow`

Launch `coq.nvim` with a greeting.

### `COQdeps`

`:COQdeps` will install all of `coq.nvim`'s dependencies locally.

Dependencies will be privately installed inside `coq.nvim`'s git root under `.vars/runtime`.

Running `rm -rf` on `coq_nvim/` will cleanly remove everything `coq.nvim` installs to your local system.

### `COQstats`

Launch a window and show performance data.
