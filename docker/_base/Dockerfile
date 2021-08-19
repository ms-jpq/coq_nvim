FROM ubuntu:focal


ENV TERM=xterm-256color
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --yes -- software-properties-common && \
    add-apt-repository ppa:neovim-ppa/unstable && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --yes -- \
    python3-venv git neovim universal-ctags tmux && \
    rm -rf /var/lib/apt/lists/*
