FROM coq_base


ADD https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim /root/.config/nvim/autoload/plug.vim
COPY ./docker/vimplug /
WORKDIR /root/.config/nvim/plugged
RUN git clone --depth=1 -- https://github.com/ms-jpq/chadtree.git && \
    git clone --depth=1 -- https://github.com/ms-jpq/coq.artifacts.git
RUN cd /root/.config/nvim/plugged/chadtree || exit 1 && \
    python3 -m chadtree deps


COPY ./ /root/.config/nvim/plugged/coq_nvim
RUN cd /root/.config/nvim/plugged/coq_nvim || exit 1 && \
    python3 -m coq deps

