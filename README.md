# carolina-codes-fstar

Read-only v1 polyglot API for Carolina Code Conference. **F\*** extracted with `--codegen OCaml`, served over **OCaml Unix** sockets.

Catalog SQL uses libpq against PostgreSQL `v1_*` views. Routing lives in `src/Carolina.fst`; `Carolina.handle_get` is the shipped handler. Tests drive that extracted function with a fake catalog.

```bash
make test
```

```bash
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/carolina_dev \
CAROLINA_URL=http://127.0.0.1:4000 \
POLYGLOT_REGISTER_TOKEN=dev \
PUBLIC_BASE_URL=http://127.0.0.1:4026 \
PORT=4026 \
./bin/server
```

`GET /` reports `language: "F*"` and `framework: "OCaml Unix"`. `GET /health` returns `{"status":"ok"}` without touching Postgres. Listen port is **4026**.
