# Memory

Short index of facts that stay true across sessions. Read `DECISIONS.md` before an architectural change. Update this file when one of these facts changes, and put the reason in `DECISIONS.md`. This is not a session log.

## Versions

- F* **v2026.08.30**. Identity string is `F* 2026.08.30`.
- OCaml **5.3** (`ocaml/opam:debian-12-ocaml-5.3`, opam constraint `ocaml >= 5.3.0`, local switch `5.3.0`).
- dune `>= 3.8`. API version `0.2.0`.
- ocamlformat **0.27.0**, optional, check-only. It is not in the SBOM.

## Packages

- Build: dune, ocamlfind, batteries, zarith, yojson, ppx_deriving, ppx_deriving_yojson, stdint.
- Runtime links: libpq and libgmp (`libpq5`, `libgmp10` in the image).
- libpq connect and query give up after 1 second when the peer is silent. The client receives `{"error":"unavailable"}` and the handle is dropped.
- No JVM runtime and no CRaC.

## Ports

- Local default listen port **4026**.
- Container and Fly `PORT` **8080**.
- Fly check: `GET /health`, timeout 5s, grace 40s.

## Do not format

`ocaml/Carolina.ml`, `ocaml/Prims.ml`, `ocaml/FStar_*.ml`, and `ocaml-output/`.

## Do not query

Ash tables, catalog base tables, or `v1_year_speakers`. SQL for this handler is `v1_speakers`, `v1_sponsors`, `v1_years`, `v1_talks`, `v1_sponsorships`, and `v1_year_sponsors` in the CMS database.

## Where to look

- Handler: `src/Carolina.fst`, extracted to `ocaml/Carolina.ml`, entry `Carolina.handle_get`.
- Sockets: `ocaml/serve.ml`. Process entry: `ocaml/server.ml`.
- Database: `ocaml/catalog.ml`, `ocaml/pq_stubs.c`.
- Tests: `make test` runs `ocaml/test.exe`.
- Contract: CMS `priv/api/openapi.yaml` (other git remote), not a file in this tree.
- Decisions: `DECISIONS.md` (D1 extraction through D8 idle Fly runtime).
