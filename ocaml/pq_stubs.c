#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/threads.h>
#include <errno.h>
#include <libpq-fe.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>

/* PQconnectdb and PQexec block with no deadline. A peer that accepts and
   never answers, or a connection that stops answering after startup, held
   the catalog request (and the catalog mutex) until the kernel gave up.
   Poll with this deadline and release the runtime lock so GET /health still
   runs, and so the catalog request itself can return JSON. */
#define CAROLINA_IO_DEADLINE 1.0

static double mono_now(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

/* Make a later PQfinish return. A half-open socket otherwise blocks in
   libpq's terminate send until TCP gives up. */
static void abandon(PGconn *c) {
  int fd;
  struct linger lin;
  if (c == NULL)
    return;
  fd = PQsocket(c);
  if (fd < 0)
    return;
  lin.l_onoff = 1;
  lin.l_linger = 0;
  setsockopt(fd, SOL_SOCKET, SO_LINGER, &lin, sizeof lin);
  shutdown(fd, SHUT_RDWR);
}

static int wait_socket(PGconn *c, int writing, double deadline) {
  int fd = PQsocket(c);
  if (fd < 0)
    return -1;
  for (;;) {
    double remain = deadline - mono_now();
    struct pollfd pfd;
    int ms, rc;
    if (remain <= 0.0)
      return -1;
    pfd.fd = fd;
    pfd.events = (short)((writing ? POLLOUT : POLLIN) | POLLERR | POLLHUP);
    ms = (int)(remain * 1000.0);
    if (ms < 1)
      ms = 1;
    rc = poll(&pfd, 1, ms);
    if (rc < 0) {
      if (errno == EINTR)
        continue;
      return -1;
    }
    if (rc == 0)
      return -1;
    return 0;
  }
}

static void copy_err(char *err, size_t errlen, const char *msg, const char *fallback) {
  if (!msg || !msg[0])
    msg = fallback;
  snprintf(err, errlen, "%s", msg);
}

static PGconn *connect_deadline(const char *dsn, char *err, size_t errlen) {
  PGconn *c = PQconnectStart(dsn);
  PostgresPollingStatusType st;
  double deadline;
  if (c == NULL) {
    copy_err(err, errlen, NULL, "connect failed");
    return NULL;
  }
  if (PQstatus(c) == CONNECTION_BAD || PQsetnonblocking(c, 1) != 0) {
    copy_err(err, errlen, PQerrorMessage(c), "connect failed");
    abandon(c);
    PQfinish(c);
    return NULL;
  }
  deadline = mono_now() + CAROLINA_IO_DEADLINE;
  st = PGRES_POLLING_WRITING;
  while (st != PGRES_POLLING_OK) {
    int writing;
    if (st == PGRES_POLLING_FAILED) {
      copy_err(err, errlen, PQerrorMessage(c), "connect failed");
      abandon(c);
      PQfinish(c);
      return NULL;
    }
    writing = st == PGRES_POLLING_WRITING;
    if (wait_socket(c, writing, deadline) < 0) {
      copy_err(err, errlen, NULL, "connect timeout");
      abandon(c);
      PQfinish(c);
      return NULL;
    }
    st = PQconnectPoll(c);
  }
  if (PQstatus(c) != CONNECTION_OK) {
    copy_err(err, errlen, PQerrorMessage(c), "connect failed");
    abandon(c);
    PQfinish(c);
    return NULL;
  }
  return c;
}

/* Caller owns the PGconn and finishes it after a NULL return. */
static PGresult *exec_deadline(PGconn *c, const char *sql, int n, const char **vals,
                               char *err, size_t errlen) {
  double deadline = mono_now() + CAROLINA_IO_DEADLINE;
  PGresult *first = NULL;
  int sent = n == 0 ? PQsendQuery(c, sql)
                    : PQsendQueryParams(c, sql, n, NULL, vals, NULL, NULL, 0);
  if (sent != 1) {
    copy_err(err, errlen, PQerrorMessage(c), "send failed");
    return NULL;
  }
  for (;;) {
    int flush = PQflush(c);
    PGresult *res;
    if (flush < 0) {
      copy_err(err, errlen, PQerrorMessage(c), "flush failed");
      break;
    }
    if (flush > 0) {
      if (wait_socket(c, 1, deadline) < 0) {
        copy_err(err, errlen, NULL, "query timeout");
        break;
      }
      continue;
    }
    if (PQconsumeInput(c) != 1) {
      copy_err(err, errlen, PQerrorMessage(c), "consume failed");
      break;
    }
    if (PQisBusy(c)) {
      if (wait_socket(c, 0, deadline) < 0) {
        copy_err(err, errlen, NULL, "query timeout");
        break;
      }
      continue;
    }
    res = PQgetResult(c);
    if (res == NULL)
      goto done;
    if (first == NULL)
      first = res;
    else
      PQclear(res);
  }
  if (first != NULL)
    PQclear(first);
  abandon(c);
  return NULL;
done:
  if (first == NULL) {
    copy_err(err, errlen, PQerrorMessage(c), "null result");
    abandon(c);
    return NULL;
  }
  if (PQresultStatus(first) != PGRES_TUPLES_OK &&
      PQresultStatus(first) != PGRES_COMMAND_OK) {
    copy_err(err, errlen, PQresultErrorMessage(first), "null result");
    PQclear(first);
    abandon(c);
    return NULL;
  }
  return first;
}

CAMLprim value carolina_pq_connect(value vdsn) {
  CAMLparam1(vdsn);
  char *dsn = caml_stat_strdup(String_val(vdsn));
  PGconn *c;
  char err[1024];
  err[0] = 0;
  caml_release_runtime_system();
  c = connect_deadline(dsn, err, sizeof err);
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
  abandon(c);
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
  int i, r, f, nt, nf;
  PGresult *res;
  if (n > 32)
    caml_failwith("too many params");
  sql = caml_stat_strdup(String_val(vsql));
  for (i = 0; i < n; i++) {
    stored[i] = caml_stat_strdup(String_val(Field(vargs, i)));
    vals[i] = stored[i];
  }
  err[0] = 0;
  caml_release_runtime_system();
  res = exec_deadline(c, sql, n, vals, err, sizeof err);
  caml_acquire_runtime_system();
  caml_stat_free(sql);
  for (i = 0; i < n; i++)
    caml_stat_free(stored[i]);
  if (res == NULL)
    caml_failwith(err[0] ? err : "query failed");
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
