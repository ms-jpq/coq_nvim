FROM ubuntu:focal

ENV TERM=xterm-256color
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --yes python3-venv neovim git && \
    rm -rf /var/lib/apt/lists/*


ADD https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim /root/.config/nvim/autoload/plug.vim
COPY ./fs /

WORKDIR /root/.config/nvim/plugged/coq_nvim
# RUN python3 -m coq deps
