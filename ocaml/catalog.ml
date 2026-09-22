(* libpq catalog used by the extracted F* handler. *)

type conn

external pq_connect : string -> conn = "carolina_pq_connect"

external pq_exec : conn -> string -> string array -> (string * string) list list
  = "carolina_pq_exec"

let sql_count = ref 0
let connect_count = ref 0
let hook : (string -> string list -> Carolina.row list) option ref = ref None
let live : conn option ref = ref None

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

let ensure () =
  match !live with
  | Some c -> c
  | None ->
      incr connect_count;
      let c = pq_connect (dsn ()) in
      live := Some c;
      c

let query sql args : Carolina.row list =
  incr sql_count;
  match !hook with
  | Some f -> f sql args
  | None ->
      let c = ensure () in
      pq_exec c sql (Array.of_list args)
