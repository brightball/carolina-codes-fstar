# Decisions

Binding decisions for this F* extraction and the OCaml Unix service that serves it.

F* builds pin the compiler and the extracted runtime together. The OCaml side owns sockets and libpq, which sit outside the extracted proof. Each entry below is the current decision, its status, and the consequence for later changes. There is no amendment history. When a decision changes, edit that entry in place and update `MEMORY.md` in the same commit. Do not append a session log here.

## D1. Extract F* v2026.08.30 to OCaml

Status: accepted

Decision: The handler is `src/Carolina.fst`, extracted with `fstar.exe --codegen OCaml` from the **F\* v2026.08.30** tarball. `ocaml/Prims.ml` and `ocaml/FStar_*.ml` are copied from that same compiler's library. `ocaml/Carolina.ml` is generated output, not the source of truth.

Consequence: Bump F* only by changing the tarball, re-extracting, and refreshing the runtime files together. Do not hand-edit the extracted handler to change behavior. Do not run ocamlformat on `Carolina.ml`, `Prims.ml`, or `FStar_*.ml`.

## D2. Serve the extraction with OCaml Unix

Status: accepted

Decision: HTTP is the OCaml `Unix` library in `ocaml/serve.ml`. The process entry is `ocaml/server.ml`. There is no web framework. `Carolina.handle_get` stays a pure function of the catalog, the path, and the year query.

Consequence: Timeouts, threads, and registration live in `serve.ml`. Do not push socket I/O into the F* module.

## D3. libpq against CMS v1 views

Status: accepted

Decision: Catalog SQL uses libpq (`ocaml/pq_stubs.c`, `ocaml/catalog.ml`) against PostgreSQL `v1_*` views in the CMS database. The HTTP contract is the CMS OpenAPI file, not an `openapi.yaml` or `db/*.sql` tree in this repo. Year-scoped speakers are filtered with `v1_talks`, not `v1_year_speakers`.

Consequence: Do not vendor the starter schema, seed data, or Compose Postgres. Do not query Ash tables or base tables. Do not add a `v1_year_speakers` query to match a different sibling.

## D4. One libpq connection, dropped when it dies

Status: accepted

Decision: Catalog queries share one `PGconn`, guarded by a mutex. `PQconnectdb` and `PQexec` release the OCaml runtime lock while they block. If the connection is `CONNECTION_BAD`, or an exec fails and leaves it bad, the handle is finished and forgotten. The HTTP client still receives a status line and `{"error":"unavailable"}`. The next query opens a new connection.

Consequence: Do not reuse a connection that pgbouncer or a suspend cycle has killed. Do not hold the OCaml runtime lock across libpq calls, or `/health` cannot run on another thread. Do not answer a database failure by closing the socket with no HTTP response.

## D5. Accept loop stays responsive for /health

Status: accepted

Decision: Each accepted socket is handled on its own thread. Header reads give up after 5 seconds. `GET /health` returns exactly `{"status":"ok"}` and does not call the catalog, including while another request is blocked inside libpq.

Consequence: Do not go back to a single-threaded accept loop. Do not let a client that never finishes its headers occupy a handler thread without a deadline. Do not make `/health` check Postgres.

## D6. Register once, off the accept path

Status: accepted

Decision: After the listen socket is bound, one background thread POSTs the identity to `{CAROLINA_URL}/internal/api-endpoints/register`. The CMS host is resolved with `getaddrinfo`. Empty `CAROLINA_URL` or `POLYGLOT_REGISTER_TOKEN` skips the call. Any failure is logged. There is no heartbeat.

Consequence: A CMS that accepts the TCP connection and sends nothing must not delay `/health` or `/`. Do not move registration back onto the accept thread. Do not retry it on a timer.

## D7. Format and warn only on handwritten OCaml

Status: accepted

Decision: ocamlformat 0.27.0 checks `ocaml/catalog.ml`, `ocaml/serve.ml`, `ocaml/server.ml`, `ocaml/test.ml`, and their `.mli` files. The generated F* library keeps the warning suppressions in `ocaml/dune` and is not built with `-warn-error`. Handwritten OCaml and `pq_stubs.c` fail the build on warnings.

Consequence: Do not add extracted files to `HANDWRITTEN_ML`. Do not put `-warn-error` on the generated library.

## D8. Small cold runtime, idle Fly machine

Status: accepted

Decision: `make release` is `dune build --profile release`. The runtime image copies only `server.exe` onto Debian with `libpq5` and `libgmp10`. It does not contain the F* compiler or an opam switch. Fly suspends idle machines (`auto_stop_machines = "suspend"`, autostart, `min_machines_running = 0`, 256mb) and checks `GET /health`.

Consequence: Do not keep a warm machine, raise memory, or turn off suspend to paper over a blocked accept loop or a cached dead connection. Do not copy the opam switch or the F* tarball into the runtime stage.

## D9. Bound a silent database at 1 second

Status: accepted

Decision: `ocaml/pq_stubs.c` polls libpq connect and query sockets and gives up after 1 second when the peer does not answer. The runtime lock is released during that wait. On any catalog error the handle is finished, including when `PQstatus` is still `CONNECTION_OK`, and the client receives `{"error":"unavailable"}`.

Consequence: A peer that accepts and stays silent, or a connection that stops answering after startup, must not hold a catalog request until the kernel times out TCP. Do not raise this deadline past the point where that response would miss a 2 second bound. Do not reuse the handle after the deadline.
