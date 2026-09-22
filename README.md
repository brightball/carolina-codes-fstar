# carolina-codes-fstar

Read-only v1 polyglot API for Carolina Code Conference. **F\*** extracted with `--codegen OCaml`, served over **OCaml Unix** sockets.

Catalog SQL uses libpq against PostgreSQL `v1_*` views. Routing lives in `src/Carolina.fst`; `Carolina.handle_get` is the shipped handler. Tests drive that extracted function with a fake catalog.

```bash
make test        # handler tests (extracted handle_get, fake catalog)
make sast        # Semgrep CE on shipped F* / handwritten OCaml / pq_stubs.c
make vuln        # OSV-Scanner against the committed opam CycloneDX SBOM
make secrets     # gitleaks on the working tree
make fmt-check   # ocamlformat --check on handwritten OCaml only
make check       # all of the above, sequentially
make hooks       # install local pre-commit hooks
```

Pre-commit runs the same five checks (`local tests`, `static security scanner`, `3rd-party dependency scanner`, `gitleaks`, `ocamlformat`). Install once with `make hooks` (needs `pre-commit` on PATH). Emergency skip: `SKIP=local-tests,sast,vuln,secrets,fmt git commit`.

`ocamlformat` is check-only on handwritten `ocaml/catalog.ml`, `ocaml/server.ml`, and `ocaml/test.ml`. Generated F* extraction (`Carolina.ml`, `Prims.ml`, `FStar_*.ml`) is not a formatting surface.

```bash
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/carolina_dev \
CAROLINA_URL=http://127.0.0.1:4000 \
POLYGLOT_REGISTER_TOKEN=dev \
PUBLIC_BASE_URL=http://127.0.0.1:4026 \
PORT=4026 \
./bin/server
```

`GET /` reports `language: "F*"` and `framework: "OCaml Unix"`. `GET /health` returns `{"status":"ok"}` without touching Postgres. The process binds its listen socket before CMS registration, so a registry that accepts the TCP connection and sends nothing does not delay `/health` or `/`. Postgres is not contacted until a catalog route runs. Listen port is **4026**.

The container image builds with `dune build --profile release` and copies only that native binary onto a Debian runtime with `libpq` and `libgmp` (no F* compiler, no opam switch). Fly suspends idle machines (`auto_stop_machines = "suspend"`, autostart on) at 256mb and checks `GET /health`.
