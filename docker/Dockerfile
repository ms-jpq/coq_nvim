FROM ubuntu:focal

ENV TERM=xterm-256color
RUN apt-get update && \
    apt-get install -y python3-venv neovim git && \
    rm -rf /var/lib/apt/lists/*


ADD https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim /root/.config/nvim/autoload/plug.vim
COPY docker/root /
COPY . /root/.config/nvim/plugged/coq-nvim/


WORKDIR /root/.config/nvim/plugged/coq-nvim
# RUN python3 -m coq-nvim deps --xdg
