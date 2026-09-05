#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <libpq-fe.h>
#include <string.h>

CAMLprim value carolina_pq_connect(value vdsn) {
  CAMLparam1(vdsn);
  PGconn *c = PQconnectdb(String_val(vdsn));
  if (PQstatus(c) != CONNECTION_OK) {
    char buf[1024];
    snprintf(buf, sizeof buf, "%s", PQerrorMessage(c));
    PQfinish(c);
    caml_failwith(buf);
  }
  CAMLreturn(caml_copy_nativeint((intnat)c));
}

CAMLprim value carolina_pq_exec(value vconn, value vsql, value vargs) {
  CAMLparam3(vconn, vsql, vargs);
  CAMLlocal4(rows, row, pair, tmp);
  PGconn *c = (PGconn *)Nativeint_val(vconn);
  int n = Wosize_val(vargs);
  const char *vals[32];
  int i, r, f, nt, nf;
  PGresult *res;
  if (n > 32)
    caml_failwith("too many params");
  for (i = 0; i < n; i++)
    vals[i] = String_val(Field(vargs, i));
  if (n == 0)
    res = PQexec(c, String_val(vsql));
  else
    res = PQexecParams(c, String_val(vsql), n, NULL, vals, NULL, NULL, 0);
  if (!res || (PQresultStatus(res) != PGRES_TUPLES_OK &&
               PQresultStatus(res) != PGRES_COMMAND_OK)) {
    char buf[1024];
    snprintf(buf, sizeof buf, "%s", res ? PQresultErrorMessage(res) : "null result");
    if (res)
      PQclear(res);
    caml_failwith(buf);
  }
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
