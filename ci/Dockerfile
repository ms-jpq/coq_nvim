FROM ubuntu:focal


RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository ppa:neovim-ppa/unstable && \
    apt-get update && \
    apt-get install -y neovim git python3 && \
    rm -rf /var/lib/apt/lists/*

