FROM coq_base


RUN git clone --depth=1 -- https://github.com/wbthomason/packer.nvim \
    ~/.local/share/nvim/site/pack/packer/start/packer.nvim


COPY ./ /root/.config/nvim/plugged/coq_nvim
RUN cd /root/.config/nvim/plugged/coq_nvim || exit 1 && \
    python3 -m coq deps


COPY ./docker/packer /
