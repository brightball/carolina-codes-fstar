(* Drive the extracted Carolina.handle_get — the shipped F* handler. *)

let has s sub =
  let n = String.length s and m = String.length sub in
  let rec aux i = i + m <= n && (String.sub s i m = sub || aux (i + 1)) in
  m = 0 || aux 0

let row kvs : Carolina.row = kvs

let speaker =
  row
    [
      ("slug", "diana-pham");
      ("first_name", "Diana");
      ("last_name", "Pham");
      ("name", "Diana Pham");
    ]

let talk =
  row
    [
      ("slug", "talk");
      ("title", "Talk");
      ("speaker_slug", "diana-pham");
      ("year", "2026");
      ("languages", "{php}");
      ("topics", "{development}");
    ]

let year_sponsor =
  row
    [
      ("slug", "flywheel");
      ("name", "Flywheel");
      ("tier", "platinum");
      ("year", "2026");
    ]

let year_row =
  row
    [
      ("year", "2026");
      ("slug", "2026");
      ("name", "Carolina Code Conference 2026");
      ("status", "past");
    ]

let sqls = ref []

let fake (sql : string) (args : string list) : Carolina.row list =
  sqls := sql :: !sqls;
  let arg0 = match args with h :: _ -> h | [] -> "" in
  let arg1 = match args with _ :: h :: _ -> h | _ -> "" in
  if has sql "FROM v1_speakers WHERE slug =" then
    if arg0 = "diana-pham" then [ speaker ] else []
  else if has sql "FROM v1_speakers" then [ speaker ]
  else if has sql "FROM v1_talks" then [ talk ]
  else if has sql "FROM v1_year_sponsors" then
    if arg1 = "missing-sponsor" then [] else [ year_sponsor ]
  else if has sql "FROM v1_sponsors WHERE slug" then []
  else if has sql "FROM v1_sponsors" then [ year_sponsor ]
  else if has sql "FROM v1_years" then [ year_row ]
  else if has sql "FROM v1_sponsorships" then []
  else []

let failed = ref 0

let expect cond msg =
  if cond then Printf.eprintf "ok: %s\n%!" msg
  else (
    incr failed;
    Printf.eprintf "FAIL: %s\n%!" msg)

let () =
  expect (Carolina.language = "F*") "identity language is F*";
  expect (Carolina.framework = "OCaml Unix") "framework is OCaml Unix";
  expect (Carolina.language <> "F#") "not F#";
  expect (Carolina.framework <> "ASP.NET") "not ASP.NET";

  let s, b = Carolina.handle_get fake "/health" "" in
  expect (Z.to_int s = 200) "/health returns 200";
  expect (has b "\"status\"") "/health JSON has status";
  expect (has b "\"ok\"") "/health JSON has ok";

  let s, b = Carolina.handle_get fake "/health/" "" in
  expect (Z.to_int s = 200) "/health/ returns 200";
  expect (has b "ok") "/health/ body has ok";

  let s, b = Carolina.handle_get fake "/" "" in
  expect (Z.to_int s = 200) "GET / returns 200";
  expect (has b "F*") "GET / language F*";
  expect (has b "OCaml Unix") "GET / framework OCaml Unix";

  sqls := [];
  let s, b = Carolina.handle_get fake "/v1/speakers/no-such-slug" "" in
  expect (Z.to_int s = 404) "unknown speaker slug returns 404";
  expect (has b "not_found") "404 body is not_found";

  sqls := [];
  let s, b = Carolina.handle_get fake "/v1/speakers" "2026" in
  expect (Z.to_int s = 200) "year-scoped speakers return 200";
  expect (has b "\"data\"") "wrapped as data";
  expect (has b "languages") "row has languages";
  expect (has b "topics") "row has topics";
  expect (List.exists (fun q -> has q "v1_talks") !sqls) "queries v1_talks";
  expect
    (not (List.exists (fun q -> has q "v1_year_speakers") !sqls))
    "does not query v1_year_speakers";

  let s, b = Carolina.handle_get fake "/v1/sponsors" "2026" in
  expect (Z.to_int s = 200) "year-scoped sponsors return 200";
  expect (has b "tier") "row includes tier";
  expect (has b "platinum") "tier is platinum";

  let s, b = Carolina.handle_get fake "/v1/years" "" in
  expect (Z.to_int s = 200) "/v1/years returns 200";
  expect (has b "\"data\"") "years wrapped as data";

  if !failed > 0 then (
    Printf.eprintf "handler tests failed (%d)\n%!" !failed;
    exit 1);
  Printf.eprintf "handler tests passed\n%!";
  exit 0
