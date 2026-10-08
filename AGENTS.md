# carolina-codes-fstar

Read-only v1 HTTP API for the Carolina Code Conference Elixir site. The handler is **F\*** (`src/Carolina.fst`), extracted with `--codegen OCaml` (**F\* v2026.08.30**) and served by **OCaml 5.3** Unix sockets. There is no separate HTTP framework.

This repository is the finished API, not the forkable starter. It does not ship `openapi.yaml`, `db/*.sql`, Compose, or seed images. The HTTP contract lives in the CMS repo (`github.com/brightball/carolina-codes`, `priv/api/openapi.yaml` and `priv/api/AGENTS.md`). Do not implement Ash JSON:API (`application/vnd.api+json`). Siblings speak ordinary JSON over the v1 REST + SQL-view contract.

You do not need a checkout of the Elixir CMS to build or run tests here. Treat **this repo** as the workspace root. Do not assume `../elixir` or other sibling directories exist. Registration is best-effort: if `CAROLINA_URL` or `POLYGLOT_REGISTER_TOKEN` is unset, or the CMS is down, skip registration and still serve HTTP.

Before an architectural change, read `DECISIONS.md` and `MEMORY.md`. `DECISIONS.md` is the binding record (decision, status, consequence) with no amendment log. `MEMORY.md` is the short index of pins an agent would otherwise relearn. When you make a new durable decision, update both in the same change. Neither file is a session log.

## Purpose

The Phoenix app keeps at most one language API warm and reads speakers and sponsors from it. This process must:

1. Query PostgreSQL **v1 views**, never Ash resource tables.
2. Expose the v1 routes below. The CMS OpenAPI file is the payload contract. This repo does not vendor a second copy.
3. **Register once on boot** with the Elixir site (no heartbeat). Run that call off the accept path. If the site is not running, log and continue.

## Environment

| Variable | Example | Role |
| --- | --- | --- |
| `DATABASE_URL` | `postgres://postgres:postgres@127.0.0.1:5432/carolina_dev` | SQL views. `sslmode=disable` is appended when the URL does not already set it. |
| `CAROLINA_URL` | `http://127.0.0.1:4000` | Elixir site. Optional. Registration no-ops when this is unset. |
| `POLYGLOT_REGISTER_TOKEN` | `dev` | Register token. Registration no-ops when this is unset. |
| `PUBLIC_BASE_URL` | `http://127.0.0.1:4026` | URL Elixir will call. |
| `PORT` | `4026` | Listen port. Fly sets `8080` inside the image. |

Local run:

```bash
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/carolina_dev \
CAROLINA_URL=http://127.0.0.1:4000 \
POLYGLOT_REGISTER_TOKEN=dev \
PUBLIC_BASE_URL=http://127.0.0.1:4026 \
PORT=4026 \
./bin/server
```

There is no Compose file in this repo. Handler tests use a fake catalog and do not need Postgres. Live HTTP against the views needs Postgres 16 and the URL above.

## SQL views (query these)

`v1_speakers`, `v1_sponsors`, `v1_years`, `v1_talks`, `v1_sponsorships`, `v1_year_sponsors`.

The views live in the CMS database. This tree does not contain `db/*.sql`. Do not `SELECT` from base tables (`speakers`, `organizations`, `talks`, and the rest) or from Ash tables. The views are the API.

This handler does **not** query `v1_year_speakers`. Year membership for speakers comes from `v1_talks`.

## Required HTTP routes

Wrap list payloads as `{ "data": [ ... ] }` unless noted. Unknown slugs return 404 and `{"error":"not_found"}`.

- `GET /health` — liveness, body exactly `{"status":"ok"}`. Does not query the catalog, including while another request is blocked in the database.
- `GET /` — identity (`language` is `F*`, `framework` is `OCaml Unix`)
- `GET /v1/years`
- `GET /v1/speakers` and `GET /v1/speakers?year=`
- `GET /v1/speakers/{slug}` and `GET /v1/speakers/{year}/{slug}`
- `GET /v1/sponsors` and `GET /v1/sponsors?year=`
- `GET /v1/sponsors/{slug}` and `GET /v1/sponsors/{year}/{slug}`

Year-scoped speaker rows include `languages` and `topics`. Year-scoped sponsor rows include `tier`.

`photo_path` and `logo_path` are web paths returned from the view. This repo does not ship image bytes.

A catalog request whose database connection fails, is closed, or never answers still finishes with an HTTP status and a JSON body (`{"error":"unavailable"}`). A silent peer is given up after 1 second. That handle is dropped. The next catalog request opens a new connection.

A client that connects and never finishes its request headers cannot hold the accept loop. Header reads stop after 5 seconds.

## Register on boot (once)

`POST {CAROLINA_URL}/internal/api-endpoints/register`

```
Authorization: Bearer dev
Content-Type: application/json
```

`dev` is the local example. The process sends whatever `POLYGLOT_REGISTER_TOKEN` is set to.

Body fields: `language`, `language_version`, `api_version`, `framework`, `created_year`, `base_url` (`PUBLIC_BASE_URL`), `schema_version` (1), `endpoints` (list of GET paths). The process splices `base_url` onto the identity object from `Carolina.identity_json`.

Do not heartbeat. Elixir keep-alives the currently warm API.

Registration runs on a background thread **after** the listen socket is bound, and it resolves the CMS with `getaddrinfo` (IPv6 included). A registry that accepts the TCP connection and sends nothing must not block `/health` or `/`. If `CAROLINA_URL` or the token is empty, or the POST fails, log and keep serving.

## Layout

| Path | Role |
| --- | --- |
| `src/Carolina.fst` | F* handler. `Carolina.handle_get` is the shipped function. |
| `ocaml/Carolina.ml` | Extraction output. Not a source of truth and not an ocamlformat surface. |
| `ocaml/Prims.ml`, `ocaml/FStar_*.ml` | Runtime copied from the same F* `v2026.08.30` tree that extracts the handler. |
| `ocaml/serve.ml` | Listen, accept, header deadline, per-connection threads. |
| `ocaml/server.ml` | Process entry. Calls `Serve.run`. |
| `ocaml/catalog.ml`, `ocaml/pq_stubs.c` | libpq connection cache and stubs. |
| `ocaml/test.ml` | `make test`. Drives extracted `handle_get` and the shipped listen/accept path. |
| `Dockerfile` | Multi-stage image. Build with F*; runtime is the native binary plus `libpq5` and `libgmp10`. Do not replace it with a starter image. |
| `fly.toml` | This app. Suspend when idle, autostart, `min_machines_running = 0`, 256mb, `GET /health`. |
| `DECISIONS.md` | Binding architectural decisions. |
| `MEMORY.md` | Index of versions, ports, and things not to relearn. |

## Checklist

- OpenAPI paths return 200 with the CMS JSON shapes (404 and `not_found` on an unknown slug)
- `?year=` speaker rows include `languages` and `topics`; sponsor rows include `tier`
- Register runs once, off the accept path; no-ops if the Elixir site is down
- `GET /health` is exactly `{"status":"ok"}` and does not touch Postgres, even during a stalled catalog call
- A dead database connection is dropped and the client still receives JSON
- No writes; no Ash table names; no `v1_year_speakers` query
- ocamlformat checks handwritten OCaml only
- Read `DECISIONS.md` and `MEMORY.md` before changing the architecture, and update them when a decision changes
