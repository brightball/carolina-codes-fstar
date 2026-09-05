(* Carolina Code Conference polyglot API — F* handler.
   Extracted to OCaml with --codegen OCaml. Catalog is injected so tests
   drive this same handle_get without a live listen. *)
module Carolina

open FStar.All
open FStar.List.Tot
open FStar.String
open FStar.Char

let language: string = "F*"
let framework: string = "OCaml Unix"
let api_version: string = "0.2.0"
let created_year: int = 2026
let schema_version: int = 1

type row = list (string & string)
type catalog = string -> list string -> list row

let speaker_cols: string =
  "slug, first_name, last_name, name, tagline, bio, company, location, photo_path, twitter_url, linkedin_url, website_url, github_url, featured"
let year_sponsor_cols: string =
  "slug, name, website, logo_path, description, blurb, tier, featured, year, twitter_url, linkedin_url, youtube_url, instagram_url, facebook_url"
let sponsor_cols: string =
  "slug, name, website, logo_path, description, twitter_url, linkedin_url, youtube_url, instagram_url, facebook_url"
let talk_cols: string =
  "slug, title, description, format, youtube_id, year, speaker_slug, languages, topics"

let rec pos_to_string (n: nat): Tot string =
  let d = n % 10 in
  let c = char_of_int (48 + d) in
  if n < 10 then string_of_char c
  else pos_to_string (n / 10) ^ string_of_char c

let show_int (n: int): ML string =
  if n < 0 then "-" ^ pos_to_string (0 - n)
  else pos_to_string n

let rec parse_digits (cs: list char) (acc: int): ML int =
  match cs with
  | [] -> acc
  | c :: tl -> parse_digits tl (acc * 10 + (int_of_char c - 48))

let parse_int (s: string): ML int = parse_digits (list_of_string s) 0

let eq (a b: string): Tot bool = compare a b = 0

let rec contains_chars (hay: list char) (needle: list char): ML bool =
  match hay with
  | [] -> isEmpty needle
  | _ :: tl ->
    let rec prefix (h n: list char): ML bool =
      match n with
      | [] -> true
      | nh :: nt ->
        (match h with
         | [] -> false
         | hh :: ht -> int_of_char hh = int_of_char nh && prefix ht nt)
    in
    prefix hay needle || contains_chars tl needle

let contains (hay needle: string): ML bool =
  contains_chars (list_of_string hay) (list_of_string needle)

let dq_char: char = char_of_int 34
let bs_char: char = char_of_int 92
let n_char: char = char_of_int 110
let r_char: char = char_of_int 114
let slash_char: char = char_of_int 47
let lbrace: char = char_of_int 123
let rbrace: char = char_of_int 125
let lbrack: char = char_of_int 91
let rbrack: char = char_of_int 93
let comma_char: char = char_of_int 44
let space_char: char = char_of_int 32
let dq: string = string_of_char dq_char

let rec escape_chars (cs: list char): ML (list char) =
  match cs with
  | [] -> []
  | c :: tl ->
    let n = int_of_char c in
    if n = 34 then bs_char :: dq_char :: escape_chars tl
    else if n = 92 then bs_char :: bs_char :: escape_chars tl
    else if n = 10 then bs_char :: n_char :: escape_chars tl
    else if n = 13 then bs_char :: r_char :: escape_chars tl
    else c :: escape_chars tl

let json_quote (s: string): ML string =
  dq ^ string_of_list (escape_chars (list_of_string s)) ^ dq

let rec get_field (r: row) (k: string): ML string =
  match r with
  | [] -> ""
  | (kk, v) :: tl -> if eq kk k then v else get_field tl k

let rec is_digits (cs: list char): ML bool =
  match cs with
  | [] -> false
  | [c] ->
    let n = int_of_char c in
    n >= 48 && n <= 57
  | c :: tl ->
    let n = int_of_char c in
    n >= 48 && n <= 57 && is_digits tl

let is_year (s: string): ML bool = is_digits (list_of_string s)

let normalize (path: string): Tot string =
  let n = length path in
  if n = 0 then "/"
  else if n > 1 && int_of_char (index path (n - 1)) = 47
  then sub path 0 (n - 1)
  else path

let split_path (path: string): Tot (list string) =
  filter (fun p -> not (eq p "")) (split [slash_char] path)

let rec at (xs: list string) (i: nat): Tot string =
  match xs with
  | [] -> ""
  | h :: t -> if i = 0 then h else at t (i - 1)

let rec join_json (parts: list string): ML string =
  match parts with
  | [] -> ""
  | [p] -> p
  | h :: t -> h ^ "," ^ join_json t

let parse_pg_array (raw: string): ML (list string) =
  let cs = list_of_string raw in
  let stripped =
    match cs with
    | ch :: rest ->
      if int_of_char ch = 123 then
        (match rev rest with
         | ch2 :: mid -> if int_of_char ch2 = 125 then rev mid else cs
         | _ -> cs)
      else if int_of_char ch = 91 then
        (match rev rest with
         | ch2 :: mid -> if int_of_char ch2 = 93 then rev mid else cs
         | _ -> cs)
      else cs
    | _ -> cs
  in
  if isEmpty stripped then []
  else
    let rec loop (cur: list char) (xs: list char): ML (list string) =
      match xs with
      | [] ->
        let p = string_of_list (rev cur) in
        if eq p "" then [] else [p]
      | c :: tl ->
        if int_of_char c = 44
        then
          let p = string_of_list (rev cur) in
          (if eq p "" then [] else [p]) @ loop [] tl
        else if int_of_char c = 34 || int_of_char c = 32
        then loop cur tl
        else loop (c :: cur) tl
    in
    loop [] stripped

let rec uniq (xs: list string): ML (list string) =
  match xs with
  | [] -> []
  | h :: t -> if existsb (eq h) t then uniq t else h :: uniq t

let rec collect_tags (talks: list row) (key: string): ML (list string) =
  match talks with
  | [] -> []
  | t :: tl -> parse_pg_array (get_field t key) @ collect_tags tl key

let rec map_quote (xs: list string): ML (list string) =
  match xs with
  | [] -> []
  | h :: t -> json_quote h :: map_quote t

let tags_json (talks: list row) (key: string): ML string =
  "[" ^ join_json (map_quote (uniq (collect_tags talks key))) ^ "]"

let field_json (k v: string): ML string =
  if eq k "languages" || eq k "topics"
  then "[" ^ join_json (map_quote (parse_pg_array v)) ^ "]"
  else if eq k "year" then show_int (parse_int v)
  else if eq k "featured"
  then (if eq v "t" || eq v "true" || eq v "1" then "true" else "false")
  else json_quote v

let rec row_fields (r: row): ML (list string) =
  match r with
  | [] -> []
  | (k, v) :: tl -> (json_quote k ^ ":" ^ field_json k v) :: row_fields tl

let row_json (r: row): ML string = "{" ^ join_json (row_fields r) ^ "}"

let rec row_strs (rs: list row): ML (list string) =
  match rs with
  | [] -> []
  | r :: tl -> row_json r :: row_strs tl

let rows_json (rs: list row): ML string =
  "[" ^ join_json (row_strs rs) ^ "]"

let rec year_strs (rs: list row): ML (list string) =
  match rs with
  | [] -> []
  | r :: tl -> show_int (parse_int (get_field r "year")) :: year_strs tl

let years_json (rs: list row): ML string =
  "[" ^ join_json (year_strs rs) ^ "]"

let other_years_json (rs: list row) (year: int): ML string =
  let rec go (xs: list row): ML (list string) =
    match xs with
    | [] -> []
    | r :: tl ->
      let y = parse_int (get_field r "year") in
      if y = year then go tl else show_int y :: go tl
  in
  "[" ^ join_json (go rs) ^ "]"

let comma_field (k v: string): ML string = "," ^ json_quote k ^ ":" ^ v

let wrap_data (inner: string): ML string = "{" ^ json_quote "data" ^ ":" ^ inner ^ "}"
let health_json (): ML string = "{" ^ json_quote "status" ^ ":" ^ json_quote "ok" ^ "}"
let not_found_json (): ML string = "{" ^ json_quote "error" ^ ":" ^ json_quote "not_found" ^ "}"

let endpoint (path: string) (query: string): ML string =
  "{" ^ json_quote "method" ^ ":" ^ json_quote "GET" ^ "," ^
  json_quote "path" ^ ":" ^ json_quote path ^ "," ^
  json_quote "query" ^ ":" ^ query ^ "}"

let identity_json (lang_version: string): ML string =
  "{" ^
  json_quote "language" ^ ":" ^ json_quote language ^ "," ^
  json_quote "language_version" ^ ":" ^ json_quote lang_version ^ "," ^
  json_quote "api_version" ^ ":" ^ json_quote api_version ^ "," ^
  json_quote "framework" ^ ":" ^ json_quote framework ^ "," ^
  json_quote "created_year" ^ ":2026," ^
  json_quote "schema_version" ^ ":1," ^
  json_quote "endpoints" ^ ":[" ^
  endpoint "/" "[]" ^ "," ^
  endpoint "/health" "[]" ^ "," ^
  endpoint "/v1/years" "[]" ^ "," ^
  endpoint "/v1/speakers" ("[" ^ json_quote "year" ^ "]") ^ "," ^
  endpoint "/v1/speakers/:slug" "[]" ^ "," ^
  endpoint "/v1/speakers/:year/:slug" "[]" ^ "," ^
  endpoint "/v1/sponsors" ("[" ^ json_quote "year" ^ "]") ^ "," ^
  endpoint "/v1/sponsors/:slug" "[]" ^ "," ^
  endpoint "/v1/sponsors/:year/:slug" "[]" ^
  "]}"

let talks_for (cat: catalog) (slug: string) (year: string): ML (list row) =
  if eq year ""
  then cat ("SELECT " ^ talk_cols ^ " FROM v1_talks WHERE speaker_slug = $1 ORDER BY year DESC") [slug]
  else cat ("SELECT " ^ talk_cols ^ " FROM v1_talks WHERE speaker_slug = $1 AND year = $2 ORDER BY year DESC") [slug; year]

let talk_years (cat: catalog) (slug: string): ML (list row) =
  cat "SELECT DISTINCT year FROM v1_talks WHERE speaker_slug = $1 ORDER BY year DESC" [slug]

let sponsor_years (cat: catalog) (slug: string): ML (list row) =
  cat "SELECT DISTINCT year FROM v1_sponsorships WHERE sponsor_slug = $1 ORDER BY year DESC" [slug]

let rec filter_talks (talks: list row) (slug: string): ML (list row) =
  match talks with
  | [] -> []
  | t :: tl ->
    if eq (get_field t "speaker_slug") slug
    then t :: filter_talks tl slug
    else filter_talks tl slug

let rec filter_years (ys: list row) (slug: string): ML (list row) =
  match ys with
  | [] -> []
  | t :: tl ->
    if eq (get_field t "speaker_slug") slug
    then t :: filter_years tl slug
    else filter_years tl slug

let rec speaker_list_json (speakers talks years: list row) (year: int): ML (list string) =
  match speakers with
  | [] -> []
  | sp :: tl ->
    let slug = get_field sp "slug" in
    let mine = filter_talks talks slug in
    let ys = filter_years years slug in
    let body = row_json sp in
    let n = length body in
    let open_obj = if n > 0 then sub body 0 (n - 1) else "{" in
    (open_obj ^
     comma_field "year" (show_int year) ^
     comma_field "talks" (rows_json mine) ^
     comma_field "languages" (tags_json mine "languages") ^
     comma_field "topics" (tags_json mine "topics") ^
     comma_field "years" (years_json ys) ^
     "}") :: speaker_list_json tl talks years year

let list_speakers_json (cat: catalog) (year: string): ML string =
  if eq year ""
  then rows_json (cat ("SELECT " ^ speaker_cols ^ " FROM v1_speakers ORDER BY last_name, first_name") [])
  else
    let speakers =
      cat ("SELECT " ^ speaker_cols ^
           " FROM v1_speakers WHERE slug IN (SELECT speaker_slug FROM v1_talks WHERE year = $1) ORDER BY last_name, first_name")
          [year]
    in
    let talks =
      cat ("SELECT " ^ talk_cols ^ " FROM v1_talks WHERE year = $1 ORDER BY speaker_slug, year DESC") [year]
    in
    let years =
      cat ("SELECT DISTINCT speaker_slug, year FROM v1_talks WHERE speaker_slug IN (SELECT speaker_slug FROM v1_talks WHERE year = $1) ORDER BY speaker_slug, year DESC")
          [year]
    in
    "[" ^ join_json (speaker_list_json speakers talks years (parse_int year)) ^ "]"

let handle_get (cat: catalog) (path0: string) (year_query: string): ML (int & string) =
  let path = normalize path0 in
  let parts = split_path path in
  let n = length parts in
  if eq path "/health" then (200, health_json ())
  else if eq path "/" then (200, identity_json "F* 2026.08.30")
  else if eq path "/v1/years" then
    (200, wrap_data (rows_json (cat "SELECT year, slug, name, status FROM v1_years ORDER BY year DESC" [])))
  else if eq path "/v1/speakers" then
    (200, wrap_data (list_speakers_json cat year_query))
  else if n = 4 && eq (at parts 0) "v1" && eq (at parts 1) "speakers" && is_year (at parts 2) then
    let year = at parts 2 in
    let slug = at parts 3 in
    let speaker = cat ("SELECT " ^ speaker_cols ^ " FROM v1_speakers WHERE slug = $1") [slug] in
    match speaker with
    | [] -> (404, not_found_json ())
    | sp :: _ ->
      let talks = talks_for cat slug year in
      (match talks with
       | [] -> (404, not_found_json ())
       | _ ->
        let years = talk_years cat slug in
        let y = parse_int year in
        let body = row_json sp in
        let m = length body in
        let open_obj = if m > 0 then sub body 0 (m - 1) else "{" in
        (200, wrap_data (open_obj ^
          comma_field "year" (show_int y) ^
          comma_field "years" (years_json years) ^
          comma_field "other_years" (other_years_json years y) ^
          comma_field "talks" (rows_json talks) ^
          comma_field "languages" (tags_json talks "languages") ^
          comma_field "topics" (tags_json talks "topics") ^
          "}")))
  else if n = 3 && eq (at parts 0) "v1" && eq (at parts 1) "speakers" then
    let slug = at parts 2 in
    let speaker = cat ("SELECT " ^ speaker_cols ^ " FROM v1_speakers WHERE slug = $1") [slug] in
    match speaker with
    | [] -> (404, not_found_json ())
    | sp :: _ ->
      let talks = talks_for cat slug "" in
      let years = talk_years cat slug in
      let body = row_json sp in
      let m = length body in
      let open_obj = if m > 0 then sub body 0 (m - 1) else "{" in
      (200, wrap_data (open_obj ^
        comma_field "talks" (rows_json talks) ^
        comma_field "years" (years_json years) ^
        "}"))
  else if eq path "/v1/sponsors" then
    if not (eq year_query "")
    then
      (200, wrap_data (rows_json (cat ("SELECT " ^ year_sponsor_cols ^ " FROM v1_year_sponsors WHERE year = $1 ORDER BY name") [year_query])))
    else
      (200, wrap_data (rows_json (cat ("SELECT " ^ sponsor_cols ^ " FROM v1_sponsors ORDER BY name") [])))
  else if n = 4 && eq (at parts 0) "v1" && eq (at parts 1) "sponsors" && is_year (at parts 2) then
    let year = at parts 2 in
    let slug = at parts 3 in
    let rows = cat ("SELECT " ^ year_sponsor_cols ^ " FROM v1_year_sponsors WHERE year = $1 AND slug = $2") [year; slug] in
    match rows with
    | [] -> (404, not_found_json ())
    | sp :: _ ->
      let years = sponsor_years cat slug in
      let y = parse_int year in
      let body = row_json sp in
      let m = length body in
      let open_obj = if m > 0 then sub body 0 (m - 1) else "{" in
      (200, wrap_data (open_obj ^
        comma_field "years" (years_json years) ^
        comma_field "other_years" (other_years_json years y) ^
        "}"))
  else if n = 3 && eq (at parts 0) "v1" && eq (at parts 1) "sponsors" then
    let slug = at parts 2 in
    let rows = cat ("SELECT " ^ sponsor_cols ^ " FROM v1_sponsors WHERE slug = $1") [slug] in
    match rows with
    | [] -> (404, not_found_json ())
    | sp :: _ ->
      let sps = cat "SELECT * FROM v1_sponsorships WHERE sponsor_slug = $1" [slug] in
      let body = row_json sp in
      let m = length body in
      let open_obj = if m > 0 then sub body 0 (m - 1) else "{" in
      (200, wrap_data (open_obj ^ comma_field "sponsorships" (rows_json sps) ^ "}"))
  else (404, not_found_json ())
