(* Thin OCaml Unix HTTP over the extracted F* Carolina.handle_get. *)

let env name default =
  match Sys.getenv_opt name with Some s when s <> "" -> s | _ -> default

let listen_port () = try int_of_string (env "PORT" "4026") with _ -> 4026

(* A client that never finishes the headers must not keep a handler thread. *)
let header_timeout = 5.0

let rec read_request fd buf pos deadline =
  if pos >= Bytes.length buf then failwith "request too large";
  let remain = deadline -. Unix.gettimeofday () in
  if remain <= 0. then failwith "header timeout";
  match Unix.select [ fd ] [] [] remain with
  | exception Unix.Unix_error (Unix.EINTR, _, _) ->
      read_request fd buf pos deadline
  | [], _, _ -> failwith "header timeout"
  | _ -> (
      match Unix.read fd buf pos (Bytes.length buf - pos) with
      | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) ->
          read_request fd buf pos deadline
      | exception Unix.Unix_error (Unix.EINTR, _, _) ->
          read_request fd buf pos deadline
      | 0 -> pos
      | n ->
          let pos = pos + n in
          let s = Bytes.sub_string buf 0 pos in
          if has s "\r\n\r\n" then pos else read_request fd buf pos deadline)

and has s sub =
  let n = String.length s and m = String.length sub in
  let rec aux i = i + m <= n && (String.sub s i m = sub || aux (i + 1)) in
  m = 0 || aux 0

let first_line s =
  match String.split_on_char '\n' s with h :: _ -> String.trim h | [] -> ""

let parse_target line =
  match String.split_on_char ' ' line with
  | _meth :: target :: _ -> target
  | _ -> "/"

let split_query target =
  match String.split_on_char '?' target with
  | path :: qs :: _ -> (path, qs)
  | path :: _ -> (path, "")
  | [] -> ("/", "")

let query_param qs name =
  let rec find = function
    | [] -> ""
    | p :: rest -> (
        match String.split_on_char '=' p with
        | k :: v :: _ when k = name -> v
        | k :: _ when k = name -> ""
        | _ -> find rest)
  in
  find (String.split_on_char '&' qs)

let write_all fd s =
  let b = Bytes.of_string s in
  let rec loop off =
    if off < Bytes.length b then
      let n = Unix.write fd b off (Bytes.length b - off) in
      loop (off + n)
  in
  loop 0

let reason_of = function
  | 404 -> "Not Found"
  | 500 -> "Internal Server Error"
  | _ -> "OK"

let respond fd status body =
  let hdr =
    Printf.sprintf
      "HTTP/1.1 %d %s\r\n\
       Content-Type: application/json\r\n\
       Content-Length: %d\r\n\
       Connection: close\r\n\
       \r\n"
      status (reason_of status) (String.length body)
  in
  write_all fd (hdr ^ body)

let unavailable = {|{"error":"unavailable"}|}

let handle_client fd cat =
  (try Unix.setsockopt fd Unix.TCP_NODELAY true with _ -> ());
  Unix.set_nonblock fd;
  (try
     let buf = Bytes.create 8192 in
     let deadline = Unix.gettimeofday () +. header_timeout in
     let n = read_request fd buf 0 deadline in
     (try Unix.clear_nonblock fd with _ -> ());
     let raw = Bytes.sub_string buf 0 n in
     let line = first_line raw in
     let path, qs = split_query (parse_target line) in
     let year = query_param qs "year" in
     let st, body =
       try Carolina.handle_get cat path year
       with e ->
         Printf.eprintf "client: %s\n%!" (Printexc.to_string e);
         (Z.of_int 500, unavailable)
     in
     respond fd (Z.to_int st) body
   with e -> Printf.eprintf "client: %s\n%!" (Printexc.to_string e));
  try Unix.clear_nonblock fd with _ -> ()

let register_once () =
  (* Any failure here is non-fatal. Callers run this off the accept path:
     Unix.read blocks forever when the CMS accepts and sends nothing. *)
  try
    let url = env "CAROLINA_URL" "" in
    let token = env "POLYGLOT_REGISTER_TOKEN" "" in
    if url = "" || token = "" then ()
    else
      let port = env "PORT" "4026" in
      let base = env "PUBLIC_BASE_URL" ("http://127.0.0.1:" ^ port) in
      let body =
        Carolina.identity_json "F* 2026.08.30" |> fun id ->
        (* identity_json is a full object; splice base_url before the last } *)
        let n = String.length id in
        String.sub id 0 (n - 1)
        ^ ",\"base_url\":\"" ^ String.escaped base ^ "\"}"
      in
      let host, p =
        let rest =
          if String.length url >= 7 && String.sub url 0 7 = "http://" then
            String.sub url 7 (String.length url - 7)
          else url
        in
        let rest =
          match String.split_on_char '/' rest with h :: _ -> h | [] -> rest
        in
        match String.split_on_char ':' rest with
        | h :: po :: _ -> (h, int_of_string po)
        | h :: _ -> (h, 80)
        | [] -> ("127.0.0.1", 80)
      in
      let rec connect_first = function
        | [] -> failwith "no address for carolina url"
        | ai :: rest -> (
            let fd = Unix.socket ai.Unix.ai_family ai.Unix.ai_socktype 0 in
            try
              (try Unix.setsockopt fd Unix.TCP_NODELAY true with _ -> ());
              Unix.connect fd ai.Unix.ai_addr;
              fd
            with _ ->
              (try Unix.close fd with _ -> ());
              connect_first rest)
      in
      let fd =
        connect_first
          (Unix.getaddrinfo host (string_of_int p)
             [ Unix.AI_SOCKTYPE Unix.SOCK_STREAM ])
      in
      Fun.protect
        ~finally:(fun () -> try Unix.close fd with _ -> ())
        (fun () ->
          let req =
            Printf.sprintf
              "POST /internal/api-endpoints/register HTTP/1.1\r\n\
               Host: %s\r\n\
               Authorization: Bearer %s\r\n\
               Content-Type: application/json\r\n\
               Content-Length: %d\r\n\
               Connection: close\r\n\
               \r\n\
               %s"
              host token (String.length body) body
          in
          write_all fd req;
          let b = Bytes.create 512 in
          let n = Unix.read fd b 0 512 in
          let resp = Bytes.sub_string b 0 n in
          let code = try String.sub (first_line resp) 9 3 with _ -> "?" in
          Printf.eprintf "registered with elixir: %s\n%!" code)
  with e -> Printf.eprintf "register: failed %s\n%!" (Printexc.to_string e)

(* Listen is already up. A stuck registry read must not block accept. *)
let spawn_register () = ignore (Thread.create (fun () -> register_once ()) ())

let dual_stack_listen port =
  let fd = Unix.socket Unix.PF_INET6 Unix.SOCK_STREAM 0 in
  Unix.setsockopt fd Unix.SO_REUSEADDR true;
  (try Unix.setsockopt fd Unix.IPV6_ONLY false with _ -> ());
  Unix.bind fd (Unix.ADDR_INET (Unix.inet6_addr_any, port));
  Unix.listen fd 128;
  fd

let bound_port fd =
  match Unix.getsockname fd with
  | Unix.ADDR_INET (_, port) -> port
  | Unix.ADDR_UNIX _ -> failwith "listen socket is not inet"

(* Sockets accepted by the shipped loop. Tests wait on this so a silent
   client is inside the handler before they issue GET /health. *)
let accepted = ref 0

(* Catalog I/O blocks inside libpq. Handle each socket on its own thread so
   a slow or reset database cannot stall GET /health on the accept loop. *)
let rec accept_loop fd cat =
  match Unix.accept fd with
  | exception Unix.Unix_error (Unix.EINTR, _, _) -> accept_loop fd cat
  | client, _ ->
      incr accepted;
      ignore
        (Thread.create
           (fun () ->
             Fun.protect
               ~finally:(fun () -> try Unix.close client with _ -> ())
               (fun () -> handle_client client cat))
           ());
      accept_loop fd cat

let start cat =
  let fd = dual_stack_listen 0 in
  let port = bound_port fd in
  ignore (Thread.create (fun () -> accept_loop fd cat) ());
  port

let run () =
  let cat sql args = Catalog.query sql args in
  let port = listen_port () in
  let fd = dual_stack_listen port in
  Printf.printf "carolina-codes-fstar listening on [::]:%d\n%!" (bound_port fd);
  spawn_register ();
  accept_loop fd cat
