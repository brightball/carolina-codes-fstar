(* libpq catalog used by the extracted F* handler. *)

type conn

external pq_connect : string -> conn = "carolina_pq_connect"

external pq_exec : conn -> string -> string array -> (string * string) list list
  = "carolina_pq_exec"

external pq_ok : conn -> bool = "carolina_pq_ok"
external pq_finish : conn -> unit = "carolina_pq_finish"

let sql_count = ref 0
let connect_count = ref 0
let hook : (string -> string list -> Carolina.row list) option ref = ref None
let live : conn option ref = ref None
let mutex = Mutex.create ()

let with_lock f =
  Mutex.lock mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock mutex) f

let has_ssl s =
  let rec aux i =
    i + 8 <= String.length s && (String.sub s i 8 = "sslmode=" || aux (i + 1))
  in
  aux 0

let dsn () =
  let raw =
    match Sys.getenv_opt "DATABASE_URL" with
    | Some s when s <> "" -> s
    | _ -> "postgres://postgres:postgres@127.0.0.1:5432/carolina_dev"
  in
  if not (has_ssl raw) then
    raw ^ (if String.contains raw '?' then "&" else "?") ^ "sslmode=disable"
  else raw

(* Suspend and pgbouncer leave CONNECTION_BAD handles. Drop them so the next
   query opens a new connection instead of failing until process restart. *)
let disconnect () =
  with_lock (fun () ->
      match !live with
      | None -> ()
      | Some c ->
          live := None;
          pq_finish c)

let rec ensure () =
  match !live with
  | Some c when pq_ok c -> c
  | Some c ->
      live := None;
      pq_finish c;
      ensure ()
  | None ->
      let c = pq_connect (dsn ()) in
      incr connect_count;
      live := Some c;
      c

let query sql args : Carolina.row list =
  incr sql_count;
  match !hook with
  | Some f -> f sql args
  | None ->
      with_lock (fun () ->
          let c = ensure () in
          try pq_exec c sql (Array.of_list args)
          with e ->
            if not (pq_ok c) then (
              live := None;
              pq_finish c);
            raise e)
