(* Thin OCaml Unix HTTP over the extracted F* Carolina.handle_get. *)

let env name default =
  match Sys.getenv_opt name with Some s when s <> "" -> s | _ -> default

let listen_port () =
  try int_of_string (env "PORT" "4026") with _ -> 4026

let rec read_request fd buf pos =
  if pos >= Bytes.length buf then failwith "request too large";
  let n = Unix.read fd buf pos (Bytes.length buf - pos) in
  if n = 0 then pos
  else
    let pos = pos + n in
    let s = Bytes.sub_string buf 0 pos in
    if has s "\r\n\r\n" then pos else read_request fd buf pos

and has s sub =
  let n = String.length s and m = String.length sub in
  let rec aux i = i + m <= n && (String.sub s i m = sub || aux (i + 1)) in
  m = 0 || aux 0

let first_line s =
  match String.split_on_char '\n' s with
  | h :: _ -> String.trim h
  | [] -> ""

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

let respond fd status body =
  let reason = if status = 404 then "Not Found" else "OK" in
  let hdr =
    Printf.sprintf
      "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
      status reason (String.length body)
  in
  write_all fd (hdr ^ body)

let handle_client fd cat =
  let buf = Bytes.create 8192 in
  let n = read_request fd buf 0 in
  let raw = Bytes.sub_string buf 0 n in
  let line = first_line raw in
  let path, qs = split_query (parse_target line) in
  let year = query_param qs "year" in
  let st, body = Carolina.handle_get cat path year in
  respond fd (Z.to_int st) body

let register_once () =
  let url = env "CAROLINA_URL" "" in
  let token = env "POLYGLOT_REGISTER_TOKEN" "" in
  if url = "" || token = "" then ()
  else
    let port = env "PORT" "4026" in
    let base = env "PUBLIC_BASE_URL" ("http://127.0.0.1:" ^ port) in
    let body =
      Carolina.identity_json "F* 2026.08.30"
      |> fun id ->
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
    try
      let addr =
        try Unix.inet_addr_of_string host
        with _ -> (Unix.gethostbyname host).Unix.h_addr_list.(0)
      in
      let fd = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
      Unix.connect fd (Unix.ADDR_INET (addr, p));
      let req =
        Printf.sprintf
          "POST /internal/api-endpoints/register HTTP/1.1\r\nHost: %s\r\nAuthorization: Bearer %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s"
          host token (String.length body) body
      in
      write_all fd req;
      let b = Bytes.create 512 in
      let n = Unix.read fd b 0 512 in
      let resp = Bytes.sub_string b 0 n in
      let code =
        try String.sub (first_line resp) 9 3 with _ -> "?"
      in
      Printf.eprintf "registered with elixir: %s\n%!" code;
      Unix.close fd
    with e -> Printf.eprintf "register: failed %s\n%!" (Printexc.to_string e)

let dual_stack_listen port =
  let fd = Unix.socket Unix.PF_INET6 Unix.SOCK_STREAM 0 in
  Unix.setsockopt fd Unix.SO_REUSEADDR true;
  (try Unix.setsockopt fd Unix.IPV6_ONLY false with _ -> ());
  Unix.bind fd (Unix.ADDR_INET (Unix.inet6_addr_any, port));
  Unix.listen fd 16;
  fd

let rec accept_loop fd cat =
  let client, _ = Unix.accept fd in
  (try handle_client client cat
   with e -> Printf.eprintf "client: %s\n%!" (Printexc.to_string e));
  (try Unix.close client with _ -> ());
  accept_loop fd cat

let () =
  let cat sql args = Catalog.query sql args in
  register_once ();
  let port = listen_port () in
  let fd = dual_stack_listen port in
  Printf.printf "carolina-codes-fstar listening on [::]:%d\n%!" port;
  accept_loop fd cat
