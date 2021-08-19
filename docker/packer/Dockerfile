FROM coq_base


COPY ./ /root/.config/nvim/plugged/coq_nvim
RUN cd /root/.config/nvim/plugged/coq_nvim || exit 1 && \
    python3 -m coq deps

