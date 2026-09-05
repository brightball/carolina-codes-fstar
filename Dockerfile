FROM ocaml/opam:debian-12-ocaml-5.3 AS build
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq-dev libgmp-dev pkg-config ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
USER opam
WORKDIR /home/opam/src
RUN curl -fsSL -o fstar.tar.gz \
      https://github.com/FStarLang/FStar/releases/download/v2026.08.30/fstar-v2026.08.30-Linux-x86_64.tar.gz \
 && tar -xzf fstar.tar.gz \
 && opam install -y dune ocamlfind batteries zarith yojson ppx_deriving ppx_deriving_yojson stdint
COPY --chown=opam:opam src ./src
COPY --chown=opam:opam ocaml ./ocaml
COPY --chown=opam:opam dune-project Makefile ./
ENV FSTAR_HOME=/home/opam/src/fstar
ENV PATH="/home/opam/src/fstar/bin:${PATH}"
RUN eval $(opam env) && make build

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /home/opam/src/_build/default/ocaml/server.exe /usr/local/bin/carolina-codes-fstar
ENV PORT=8080
EXPOSE 8080
CMD ["/usr/local/bin/carolina-codes-fstar"]
