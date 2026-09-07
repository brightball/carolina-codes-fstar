FROM ocaml/opam:debian-12-ocaml-5.3
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates libpq-dev libgmp-dev pkg-config make \
 && rm -rf /var/lib/apt/lists/*
USER opam
WORKDIR /home/opam
RUN curl -fsSL -o fstar.tar.gz https://github.com/FStarLang/FStar/releases/download/v2026.08.30/fstar-v2026.08.30-Linux-x86_64.tar.gz \
 && tar -xzf fstar.tar.gz && rm fstar.tar.gz \
 && opam install -y dune ocamlfind batteries zarith yojson ppx_deriving ppx_deriving_yojson stdint
ENV FSTAR_HOME=/home/opam/fstar
ENV PATH="/home/opam/fstar/bin:${PATH}"
ENV C_INCLUDE_PATH=/usr/include/postgresql
USER root
ENV FSTAR_HOME=/home/opam/fstar
ENV PATH="/home/opam/fstar/bin:${PATH}"
ENV C_INCLUDE_PATH=/usr/include/postgresql
