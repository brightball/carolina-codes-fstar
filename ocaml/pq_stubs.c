#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/threads.h>
#include <libpq-fe.h>
#include <stdint.h>
#include <string.h>

/* PQconnectdb and PQexec block. Releasing the runtime lock lets another
   thread answer GET /health while a catalog call is stuck in libpq. */

CAMLprim value carolina_pq_connect(value vdsn) {
  CAMLparam1(vdsn);
  char *dsn = caml_stat_strdup(String_val(vdsn));
  PGconn *c;
  int status;
  char err[1024];
  err[0] = 0;
  caml_release_runtime_system();
  c = PQconnectdb(dsn);
  status = PQstatus(c);
  if (status != CONNECTION_OK) {
    const char *msg = PQerrorMessage(c);
    snprintf(err, sizeof err, "%s", (msg && msg[0]) ? msg : "connect failed");
    PQfinish(c);
    c = NULL;
  }
  caml_acquire_runtime_system();
  caml_stat_free(dsn);
  if (c == NULL)
    caml_failwith(err[0] ? err : "connect failed");
  CAMLreturn(caml_copy_nativeint((intnat)(intptr_t)c));
}

CAMLprim value carolina_pq_ok(value vconn) {
  CAMLparam1(vconn);
  PGconn *c = (PGconn *)(intptr_t)Nativeint_val(vconn);
  CAMLreturn(Val_bool(PQstatus(c) == CONNECTION_OK));
}

CAMLprim value carolina_pq_finish(value vconn) {
  CAMLparam1(vconn);
  PGconn *c = (PGconn *)(intptr_t)Nativeint_val(vconn);
  caml_release_runtime_system();
  PQfinish(c);
  caml_acquire_runtime_system();
  CAMLreturn(Val_unit);
}

CAMLprim value carolina_pq_exec(value vconn, value vsql, value vargs) {
  CAMLparam3(vconn, vsql, vargs);
  CAMLlocal4(rows, row, pair, tmp);
  PGconn *c = (PGconn *)(intptr_t)Nativeint_val(vconn);
  int n = Wosize_val(vargs);
  const char *vals[32];
  char *stored[32];
  char *sql;
  char err[1024];
  int i, r, f, nt, nf, failed;
  PGresult *res;
  if (n > 32)
    caml_failwith("too many params");
  sql = caml_stat_strdup(String_val(vsql));
  for (i = 0; i < n; i++) {
    stored[i] = caml_stat_strdup(String_val(Field(vargs, i)));
    vals[i] = stored[i];
  }
  err[0] = 0;
  failed = 0;
  caml_release_runtime_system();
  if (n == 0)
    res = PQexec(c, sql);
  else
    res = PQexecParams(c, sql, n, NULL, vals, NULL, NULL, 0);
  if (!res || (PQresultStatus(res) != PGRES_TUPLES_OK &&
               PQresultStatus(res) != PGRES_COMMAND_OK)) {
    const char *msg = res ? PQresultErrorMessage(res) : PQerrorMessage(c);
    if (!msg || !msg[0])
      msg = "null result";
    snprintf(err, sizeof err, "%s", msg);
    if (res)
      PQclear(res);
    res = NULL;
    failed = 1;
  }
  caml_acquire_runtime_system();
  caml_stat_free(sql);
  for (i = 0; i < n; i++)
    caml_stat_free(stored[i]);
  if (failed)
    caml_failwith(err);
  nt = PQntuples(res);
  nf = PQnfields(res);
  rows = Val_emptylist;
  for (r = nt - 1; r >= 0; r--) {
    row = Val_emptylist;
    for (f = nf - 1; f >= 0; f--) {
      if (PQgetisnull(res, r, f))
        continue;
      pair = caml_alloc_tuple(2);
      Store_field(pair, 0, caml_copy_string(PQfname(res, f)));
      Store_field(pair, 1, caml_copy_string(PQgetvalue(res, r, f)));
      tmp = caml_alloc(2, 0);
      Store_field(tmp, 0, pair);
      Store_field(tmp, 1, row);
      row = tmp;
    }
    tmp = caml_alloc(2, 0);
    Store_field(tmp, 0, row);
    Store_field(tmp, 1, rows);
    rows = tmp;
  }
  PQclear(res);
  CAMLreturn(rows);
}
