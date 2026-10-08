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

let talk_years = [ row [ ("year", "2026") ]; row [ ("year", "2025") ] ]

let speaker_years =
  [
    row [ ("speaker_slug", "diana-pham"); ("year", "2026") ];
    row [ ("speaker_slug", "diana-pham"); ("year", "2025") ];
  ]

let sponsor =
  row
    [
      ("slug", "flywheel");
      ("name", "Flywheel");
      ("website", "https://getflywheel.com");
    ]

let year_sponsor =
  row
    [
      ("slug", "flywheel");
      ("name", "Flywheel");
      ("tier", "platinum");
      ("year", "2026");
    ]

let sponsorship =
  row [ ("sponsor_slug", "flywheel"); ("year", "2026"); ("tier", "platinum") ]

let sponsor_years = [ row [ ("year", "2026") ]; row [ ("year", "2025") ] ]

let year_row =
  row
    [
      ("year", "2026");
      ("slug", "2026");
      ("name", "Carolina Code Conference 2026");
      ("status", "past");
    ]

let sqls = ref []

let arg n args =
  let rec nth i = function
    | [] -> ""
    | h :: t -> if i = 0 then h else nth (i - 1) t
  in
  nth n args

let fake (sql : string) (args : string list) : Carolina.row list =
  sqls := sql :: !sqls;
  let a0 = arg 0 args in
  let a1 = arg 1 args in
  if has sql "FROM v1_speakers WHERE slug =" then
    if a0 = "diana-pham" then [ speaker ] else []
  else if has sql "FROM v1_speakers" then [ speaker ]
  else if has sql "DISTINCT speaker_slug, year" then
    if a0 = "2026" then speaker_years else []
  else if has sql "DISTINCT year FROM v1_talks" then
    if a0 = "diana-pham" then talk_years else []
  else if has sql "AND year = $2" then
    if a0 = "diana-pham" && a1 = "2026" then [ talk ] else []
  else if has sql "speaker_slug = $1" then
    if a0 = "diana-pham" then [ talk ] else []
  else if has sql "FROM v1_talks" then if a0 = "2026" then [ talk ] else []
  else if has sql "FROM v1_year_sponsors" then
    if has sql "AND slug = $2" then
      if a0 = "2026" && a1 = "flywheel" then [ year_sponsor ] else []
    else if a0 = "2026" then [ year_sponsor ]
    else []
  else if has sql "DISTINCT year FROM v1_sponsorships" then
    if a0 = "flywheel" then sponsor_years else []
  else if has sql "FROM v1_sponsorships" then
    if a0 = "flywheel" then [ sponsorship ] else []
  else if has sql "FROM v1_sponsors WHERE slug =" then
    if a0 = "flywheel" then [ sponsor ] else []
  else if has sql "FROM v1_sponsors" then [ sponsor ]
  else if has sql "FROM v1_years" then [ year_row ]
  else []

let failed = ref 0

let expect cond msg =
  if cond then Printf.eprintf "ok: %s\n%!" msg
  else (
    incr failed;
    Printf.eprintf "FAIL: %s\n%!" msg)

let rec mkdir_p path =
  if path = "" || path = "." || path = "/" then ()
  else if Sys.file_exists path then ()
  else (
    mkdir_p (Filename.dirname path);
    try Unix.mkdir path 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())

let write_file path contents =
  mkdir_p (Filename.dirname path);
  let oc = open_out_bin path in
  output_string oc contents;
  close_out oc

let write_exec path contents =
  write_file path contents;
  Unix.chmod path 0o755

let read_file path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

let rec rm_r path =
  if not (Sys.file_exists path) then ()
  else if Sys.is_directory path then (
    Array.iter
      (fun n -> if n <> "." && n <> ".." then rm_r (Filename.concat path n))
      (Sys.readdir path);
    Unix.rmdir path)
  else Sys.remove path

let repo_root () =
  let rec find dir =
    if Sys.file_exists (Filename.concat dir "dune-project") then dir
    else
      let parent = Filename.dirname dir in
      if parent = dir then failwith "dune-project not found from cwd"
      else find parent
  in
  find (Sys.getcwd ())

let env_with pairs =
  let keys =
    List.map
      (fun p ->
        match String.index_opt p '=' with
        | Some i -> String.sub p 0 i
        | None -> p)
      pairs
  in
  let keep e =
    match String.index_opt e '=' with
    | None -> true
    | Some i ->
        let k = String.sub e 0 i in
        not (List.mem k keys)
  in
  Array.of_list (pairs @ List.filter keep (Array.to_list (Unix.environment ())))

let run_capture ?(env = []) ?(cwd = ".") args =
  let old = Sys.getcwd () in
  Unix.chdir cwd;
  let stdout_r, stdout_w = Unix.pipe ~cloexec:true () in
  let pid =
    Unix.create_process_env "/bin/sh"
      (Array.of_list ("/bin/sh" :: args))
      (env_with env) Unix.stdin stdout_w stdout_w
  in
  Unix.close stdout_w;
  let ic = Unix.in_channel_of_descr stdout_r in
  let buf = Buffer.create 256 in
  (try
     while true do
       Buffer.add_string buf (input_line ic);
       Buffer.add_char buf '\n'
     done
   with End_of_file -> ());
  close_in ic;
  let _, status = Unix.waitpid [] pid in
  Unix.chdir old;
  let out = Buffer.contents buf in
  let code =
    match status with
    | Unix.WEXITED n -> n
    | Unix.WSIGNALED n -> 128 + n
    | Unix.WSTOPPED n -> 128 + n
  in
  (code, out)

let run_sh ?env ?cwd args =
  let code, out = run_capture ?env ?cwd args in
  if code = 0 then out
  else
    failwith
      (Printf.sprintf "%s exited %d\n%s" (String.concat " " args) code out)

let is_ident_char c =
  (c >= 'a' && c <= 'z')
  || (c >= 'A' && c <= 'Z')
  || (c >= '0' && c <= '9')
  || c = '_' || c = '-'

let job_header line =
  let n = String.length line in
  if n < 4 then None
  else if line.[0] <> ' ' || line.[1] <> ' ' || line.[2] = ' ' then None
  else
    let rec ident i =
      if i >= n then None
      else if is_ident_char line.[i] then ident (i + 1)
      else if line.[i] = ':' then
        let rest = String.trim (String.sub line (i + 1) (n - i - 1)) in
        if rest = "" then Some (String.sub line 2 (i - 2)) else None
      else None
    in
    ident 2

let gitea_jobs yaml =
  let ls = Array.of_list (String.split_on_char '\n' yaml) in
  let rec find_jobs i =
    if i >= Array.length ls then None
    else if ls.(i) = "jobs:" then Some (i + 1)
    else find_jobs (i + 1)
  in
  match find_jobs 0 with
  | None -> []
  | Some i0 ->
      let rec skip i acc =
        if i >= Array.length ls then List.rev acc
        else
          match job_header ls.(i) with
          | None -> skip (i + 1) acc
          | Some name ->
              let rec body j =
                if j >= Array.length ls then j
                else
                  match job_header ls.(j) with
                  | Some _ -> j
                  | None -> body (j + 1)
              in
              let j = body (i + 1) in
              let chunk =
                String.concat "\n"
                  (Array.to_list (Array.sub ls (i + 1) (j - i - 1)))
              in
              skip j ((name, chunk) :: acc)
      in
      skip i0 []

let yaml_anchor_raw_block yaml name =
  let needle = "&" ^ name in
  let ls = Array.of_list (String.split_on_char '\n' yaml) in
  let rec find i =
    if i >= Array.length ls then None
    else if has ls.(i) needle then Some i
    else find (i + 1)
  in
  match find 0 with
  | None -> None
  | Some i ->
      let header = ls.(i) in
      let indent =
        let rec lead k =
          if k >= String.length header then k
          else if header.[k] = ' ' then lead (k + 1)
          else k
        in
        lead 0
      in
      let rec take j acc =
        if j >= Array.length ls then List.rev acc
        else
          let line = ls.(j) in
          if String.trim line = "" then take (j + 1) (line :: acc)
          else
            let leading =
              let rec lead k =
                if k >= String.length line then k
                else if line.[k] = ' ' then lead (k + 1)
                else k
              in
              lead 0
            in
            if leading <= indent then List.rev acc
            else take (j + 1) (line :: acc)
      in
      Some (String.concat "\n" (header :: take (i + 1) []))

let expand_yaml_aliases yaml fragment =
  let rec aliases i acc =
    if i >= String.length fragment then acc
    else if fragment.[i] = '*' then
      let rec eat j =
        if j >= String.length fragment then j
        else if is_ident_char fragment.[j] then eat (j + 1)
        else j
      in
      let j = eat (i + 1) in
      let name = String.sub fragment (i + 1) (j - i - 1) in
      let acc = if name = "" || List.mem name acc then acc else name :: acc in
      aliases j acc
    else aliases (i + 1) acc
  in
  List.fold_left
    (fun buf name ->
      match yaml_anchor_raw_block yaml name with
      | None -> buf
      | Some body -> buf ^ "\n" ^ body)
    fragment (aliases 0 [])

let job_needs body dep =
  if dep = "" then false
  else if has body ("needs: " ^ dep) then true
  else if has body ("needs: [" ^ dep ^ "]") then true
  else
    let ls = String.split_on_char '\n' body in
    let rec walk lines in_needs needs_indent =
      match lines with
      | [] -> false
      | line :: rest ->
          let trimmed = String.trim line in
          if trimmed = "needs:" then
            let indent =
              String.length line - String.length (String.trim line)
            in
            walk rest true indent
          else if not in_needs then walk rest false needs_indent
          else if trimmed = "" then walk rest true needs_indent
          else
            let indent =
              String.length line - String.length (String.trim line)
            in
            if indent <= needs_indent then walk (line :: rest) false 0
            else if trimmed = "- " ^ dep || trimmed = "- " ^ dep ^ ":" then true
            else walk rest true needs_indent
    in
    walk ls false 0

let check_job_names = [ "test"; "sast"; "vuln"; "secrets"; "fmt" ]

let check_command = function
  | "test" -> "make test"
  | "sast" -> "make sast"
  | "vuln" -> "make vuln"
  | "secrets" -> "make secrets"
  | "fmt" -> "make fmt-check"
  | name -> failwith ("unknown check job " ^ name)

let setup_fingerprints =
  [
    "apt-get";
    "git clone";
    "git fetch";
    "git checkout";
    "opam install";
    "fstar-v2026.08.30";
    "osv-scanner_linux_amd64";
    "gitleaks_8.30.1_linux_x64.tar.gz";
    "ocamlformat.0.27.0";
    "pip install";
  ]

let restore_marker body =
  has body "ACTIONS_RUNTIME" || has body "/artifacts" || has body "ci-env"
  || has body "tar -xz" || has body "ci-restore.sh"

let non_comment_has src needle =
  List.exists
    (fun line ->
      let t = String.trim line in
      t <> "" && t.[0] <> '#' && has t needle)
    (String.split_on_char '\n' src)

let workflow_errors src =
  let errs = ref [] in
  let fail msg = errs := msg :: !errs in
  if non_comment_has src "git init" then fail "must not git init";
  if non_comment_has src "init.defaultBranch" then
    fail "must not set init.defaultBranch";
  if non_comment_has src "actions/checkout" then
    fail "must not use actions/checkout";
  if non_comment_has src "actions/upload-artifact" then
    fail "must not use actions/upload-artifact";
  if non_comment_has src "actions/download-artifact" then
    fail "must not use actions/download-artifact";
  let jobs = gitea_jobs src in
  let names = List.map fst jobs in
  List.iter
    (fun n -> if not (List.mem n names) then fail ("missing job " ^ n))
    check_job_names;
  let prepare_id =
    if List.mem "prepare" names then "prepare"
    else if List.mem "setup" names then "setup"
    else ""
  in
  (if prepare_id = "" then fail "workflow must have a prepare/setup job"
   else
     let prepare = List.assoc prepare_id jobs in
     if has prepare "needs:" then fail (prepare_id ^ " must not declare needs:");
     if not (has prepare "git clone") then
       fail (prepare_id ^ " must token-clone the repository");
     if not (has prepare "GITHUB_SHA") then
       fail (prepare_id ^ " must check out GITHUB_SHA");
     if not (has prepare "missing job token for git fetch") then
       fail (prepare_id ^ " must require the job token");
     if not (has prepare "opam install") then
       fail (prepare_id ^ " must install opam packages");
     if not (has prepare "fstar-v2026.08.30") then
       fail (prepare_id ^ " must install F*");
     if not (has prepare "ocamlformat.0.27.0") then
       fail (prepare_id ^ " must install ocamlformat");
     if not (has prepare "semgrep") then
       fail (prepare_id ^ " must install semgrep");
     if not (has prepare "osv-scanner") then
       fail (prepare_id ^ " must install osv-scanner");
     if not (has prepare "gitleaks") then
       fail (prepare_id ^ " must install gitleaks");
     if not (has prepare "ci-pack.sh") then
       fail (prepare_id ^ " must pack the environment");
     if not (has prepare "ci-artifact.sh") then
       fail (prepare_id ^ " must publish the packed environment");
     List.iter
       (fun name ->
         let raw = List.assoc name jobs in
         if not (job_needs raw prepare_id) then
           fail (name ^ " must declare needs: " ^ prepare_id);
         if not (has raw (check_command name)) then
           fail (name ^ " must run " ^ check_command name);
         if has raw "make check" then fail (name ^ " must not run make check");
         if has raw "make ci" then fail (name ^ " must not run make ci");
         if has raw "pre-commit" then fail (name ^ " must not run pre-commit");
         List.iter
           (fun other ->
             if other <> name && job_needs raw other then
               fail (name ^ " must not needs: " ^ other))
           check_job_names;
         let expanded = expand_yaml_aliases src raw in
         List.iter
           (fun fp ->
             if has expanded fp then
               fail (name ^ " must not repeat setup (" ^ fp ^ ")"))
           setup_fingerprints;
         if not (restore_marker expanded) then
           fail (name ^ " must restore the prepared payload"))
       check_job_names);
  List.rev !errs

let independent_check_jobs_yaml =
  {|
name: ci
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: apt-get update -qq && apt-get install -y git ca-certificates
      - run: |
          git clone --depth 1 --no-checkout "https://example.invalid/repo" .
          git fetch --depth 1 origin "${GITHUB_SHA}"
          git checkout --force FETCH_HEAD
      - run: opam install -y dune
      - run: make test
  sast:
    runs-on: ubuntu-latest
    steps:
      - run: apt-get update -qq && apt-get install -y git ca-certificates
      - run: |
          git clone --depth 1 --no-checkout "https://example.invalid/repo" .
          git fetch --depth 1 origin "${GITHUB_SHA}"
          git checkout --force FETCH_HEAD
      - run: pip install semgrep
      - run: make sast
  vuln:
    runs-on: ubuntu-latest
    steps:
      - run: apt-get update -qq && apt-get install -y git ca-certificates curl
      - run: |
          git clone --depth 1 --no-checkout "https://example.invalid/repo" .
          git fetch --depth 1 origin "${GITHUB_SHA}"
          git checkout --force FETCH_HEAD
      - run: |
          curl -fsSL -o /usr/local/bin/osv-scanner https://github.com/google/osv-scanner/releases/download/v2.6.0/osv-scanner_linux_amd64
          chmod +x /usr/local/bin/osv-scanner
      - run: make vuln
  secrets:
    runs-on: ubuntu-latest
    steps:
      - run: apt-get update -qq && apt-get install -y git ca-certificates curl tar
      - run: |
          git clone --depth 1 --no-checkout "https://example.invalid/repo" .
          git fetch --depth 1 origin "${GITHUB_SHA}"
          git checkout --force FETCH_HEAD
      - run: |
          curl -fsSL -o /tmp/gitleaks.tgz https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz
          tar -xzf /tmp/gitleaks.tgz -C /usr/local/bin gitleaks
      - run: make secrets
  fmt:
    runs-on: ubuntu-latest
    steps:
      - run: apt-get update -qq && apt-get install -y git ca-certificates
      - run: |
          git clone --depth 1 --no-checkout "https://example.invalid/repo" .
          git fetch --depth 1 origin "${GITHUB_SHA}"
          git checkout --force FETCH_HEAD
      - run: opam install -y ocamlformat.0.27.0
      - run: make fmt-check
|}

let anchor_copied_setup_yaml =
  {|
x-setup: &setup |
  apt-get update -qq && apt-get install -y git ca-certificates
  git clone --depth 1 --no-checkout "https://example.invalid/repo" .
  git fetch --depth 1 origin "${GITHUB_SHA}"
  git checkout --force FETCH_HEAD
  opam install -y dune ocamlformat.0.27.0
  curl -fsSL -o /usr/local/bin/osv-scanner https://github.com/google/osv-scanner/releases/download/v2.6.0/osv-scanner_linux_amd64
  curl -fsSL -o /tmp/gitleaks.tgz https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz
  pip install semgrep
jobs:
  prepare:
    runs-on: ubuntu-latest
    steps:
      - run: |
          if [ -z "$token" ]; then echo "missing job token for git fetch" >&2; exit 1; fi
          git clone --depth 1 --no-checkout "https://example.invalid/repo" .
          git fetch --depth 1 origin "${GITHUB_SHA}"
          opam install -y dune ocamlformat.0.27.0
          curl -fsSL -o /tmp/fstar.tar.gz https://github.com/FStarLang/FStar/releases/download/v2026.08.30/fstar-v2026.08.30-Linux-x86_64.tar.gz
          curl -fsSL -o /usr/local/bin/osv-scanner https://github.com/google/osv-scanner/releases/download/v2.6.0/osv-scanner_linux_amd64
          curl -fsSL -o /tmp/gitleaks.tgz https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz
          pip install semgrep
          sh scripts/ci-pack.sh /tmp/ci-env.tar.gz
          sh scripts/ci-artifact.sh upload ci-env /tmp/ci-env.tar.gz
  test:
    needs: prepare
    steps:
      - run: *setup
      - run: make test
  sast:
    needs: prepare
    steps:
      - run: *setup
      - run: make sast
  vuln:
    needs: prepare
    steps:
      - run: *setup
      - run: make vuln
  secrets:
    needs: prepare
    steps:
      - run: *setup
      - run: make secrets
  fmt:
    needs: prepare
    steps:
      - run: *setup
      - run: make fmt-check
|}

let alias_expansion_yaml =
  {|
x-setup: &setup |
  apt-get update
  git clone foo
jobs:
  test:
    steps:
      - run: *setup
|}

let ci_shape_tests () =
  let root = repo_root () in
  let workflow_path = Filename.concat root ".gitea/workflows/ci.yml" in
  expect (Sys.file_exists workflow_path) "committed Gitea workflow exists";
  let src = read_file workflow_path in
  let errs = workflow_errors src in
  List.iter (fun e -> Printf.eprintf "workflow error: %s\n%!" e) errs;
  expect (errs = []) "committed workflow is prepare-then-consume";

  expect
    (workflow_errors independent_check_jobs_yaml <> [])
    "rejects independent per-job clone/install";
  expect
    (workflow_errors anchor_copied_setup_yaml <> [])
    "rejects YAML-anchor copied setup";

  let jobs = gitea_jobs alias_expansion_yaml in
  let expanded =
    expand_yaml_aliases alias_expansion_yaml (List.assoc "test" jobs)
  in
  expect (has expanded "apt-get") "alias expansion reveals apt-get";
  expect (has expanded "git clone") "alias expansion reveals git clone";

  let pack_sh = Filename.concat root "scripts/ci-pack.sh" in
  let restore_sh = Filename.concat root "scripts/ci-restore.sh" in
  expect (Sys.file_exists pack_sh) "ci-pack.sh exists";
  expect (Sys.file_exists restore_sh) "ci-restore.sh exists";
  let restore_src = read_file restore_sh in
  List.iter
    (fun fp ->
      expect (not (has restore_src fp)) ("ci-restore.sh does not " ^ fp))
    [
      "apt-get";
      "git clone";
      "git fetch";
      "git checkout";
      "opam install";
      "fstar-v2026.08.30";
      "osv-scanner_linux_amd64";
      "gitleaks_8.30.1_linux_x64.tar.gz";
      "ocamlformat.0.27.0";
      "pip install";
    ];

  let tmp = Filename.temp_dir "fstar-ci-env" "" in
  Fun.protect
    ~finally:(fun () -> rm_r tmp)
    (fun () ->
      let work = Filename.concat tmp "work" in
      let opt = Filename.concat tmp "opt-ci" in
      write_file (Filename.concat work "Makefile") "test:\n\t@echo ok\n";
      write_file (Filename.concat work "src/Carolina.fst") "module Carolina\n";
      write_exec
        (Filename.concat work "scripts/ci-restore.sh")
        (read_file restore_sh);
      write_exec
        (Filename.concat opt "bin/osv-scanner")
        "#!/bin/sh\necho osv-scanner\n";
      write_exec
        (Filename.concat opt "bin/gitleaks")
        "#!/bin/sh\necho gitleaks\n";
      write_exec
        (Filename.concat opt "fstar/bin/fstar.exe")
        "#!/bin/sh\necho fstar\n";
      write_exec
        (Filename.concat opt "semgrep/bin/semgrep")
        "#!/bin/sh\necho semgrep\n";
      let tar = Filename.concat tmp "ci-env.tar.gz" in
      let pack_out =
        run_sh
          ~env:
            [
              "CI_WORKSPACE=" ^ work;
              "CI_OPT_CI=" ^ opt;
              "CI_PACK_OPAM=0";
              "CI_PACK_DEBS=0";
              "CI_ENV_TAR=" ^ tar;
            ]
          [ pack_sh; tar ]
      in
      expect (Sys.file_exists tar) "pack wrote CI_ENV_TAR";
      expect (has pack_out "packed") "pack reports packed tarball";

      let stubs = Filename.concat tmp "stubs" in
      List.iter
        (fun name ->
          write_exec
            (Filename.concat stubs name)
            "#!/bin/sh\necho FORBIDDEN \"$0 $*\" >&2\nexit 99\n")
        [ "apt-get"; "apt"; "opam"; "curl"; "wget"; "dpkg"; "pip"; "pip3" ];
      let path =
        stubs ^ ":" ^ try Sys.getenv "PATH" with Not_found -> "/usr/bin:/bin"
      in
      let work2 = Filename.concat tmp "work2" in
      let opt2 = Filename.concat tmp "opt2" in
      mkdir_p work2;
      mkdir_p opt2;
      let restore_out =
        run_sh
          ~env:
            [
              "PATH=" ^ path;
              "CI_ENV_TAR=" ^ tar;
              "CI_WORKSPACE=" ^ work2;
              "CI_OPT_CI=" ^ opt2;
              "CI_RESTORE_SYSTEM=0";
              "CI_PACK_OPAM=0";
              "CI_PACK_DEBS=0";
            ]
          [ restore_sh ]
      in
      expect (has restore_out "restored") "restore reports restored tree";
      expect
        (Sys.file_exists (Filename.concat work2 "Makefile"))
        "restore unpacked workspace Makefile";
      expect
        (Sys.file_exists (Filename.concat work2 "src/Carolina.fst"))
        "restore unpacked workspace sources";
      expect
        (Sys.file_exists (Filename.concat opt2 "bin/osv-scanner"))
        "restore unpacked osv-scanner";
      expect
        (Sys.file_exists (Filename.concat opt2 "bin/gitleaks"))
        "restore unpacked gitleaks";
      expect
        (Sys.file_exists (Filename.concat opt2 "fstar/bin/fstar.exe"))
        "restore unpacked F*";
      expect
        (Sys.file_exists (Filename.concat opt2 "semgrep/bin/semgrep"))
        "restore unpacked semgrep");
  Printf.eprintf "ci-shape tests passed\n%!"

let queried sub = List.exists (fun q -> has q sub) !sqls
let not_found_body = {|{"error":"not_found"}|}
let health_body = {|{"status":"ok"}|}
let reset () = sqls := []
let call path year = Carolina.handle_get fake path year
let expect_status s want msg = expect (Z.to_int s = want) msg
let expect_data b msg = expect (has b "\"data\"") msg

let runtime_stage src =
  let lines = Array.of_list (String.split_on_char '\n' src) in
  let start = ref 0 in
  for i = 0 to Array.length lines - 1 do
    let line = lines.(i) in
    if String.length line >= 5 && String.sub line 0 5 = "FROM " then start := i
  done;
  let buf = Buffer.create 256 in
  for i = !start to Array.length lines - 1 do
    if i > !start then Buffer.add_char buf '\n';
    Buffer.add_string buf lines.(i)
  done;
  Buffer.contents buf

let gate_tests () =
  let root = repo_root () in
  let dune = read_file (Filename.concat root "ocaml/dune") in
  expect
    (has dune "-warn-error +A")
    "handwritten OCaml executables fail the build on warnings";
  expect (has dune "-Werror") "C stub fails the build on warnings";
  expect
    (has dune "-w -6-8-27-32-33-37-39")
    "generated F* extraction keeps warning suppressions";
  let lib_end =
    match String.index_opt dune '(' with
    | Some _ -> (
        let marker = "(executable" in
        match
          let n = String.length marker in
          let rec find i =
            if i + n > String.length dune then 0
            else if String.sub dune i n = marker then i
            else find (i + 1)
          in
          find 0
        with
        | 0 -> dune
        | i -> String.sub dune 0 i)
    | None -> dune
  in
  expect
    (not (has lib_end "-warn-error"))
    "generated library is not built with -warn-error";

  let makefile = read_file (Filename.concat root "Makefile") in
  expect
    (has makefile "dune build --profile release")
    "release recipe requests Dune's release profile";
  expect
    (has makefile "scripts/check-sbom.sh")
    "vuln gate checks direct opam dependencies against the SBOM";
  expect
    (has makefile "osv-scanner.toml")
    "vuln scan loads the OCaml advisory ignore file";
  expect
    (Sys.file_exists (Filename.concat root "osv-scanner.toml"))
    "OCaml advisory ignore file is committed";

  let docker = read_file (Filename.concat root "Dockerfile") in
  expect (has docker "make release") "image build uses the release recipe";
  let runtime = runtime_stage docker in
  expect
    (not (has runtime "fstar.tar"))
    "runtime image does not include the F* tarball";
  expect
    (not (has runtime "opam install"))
    "runtime image does not install an opam switch";
  expect
    (not (has runtime ".opam"))
    "runtime image does not copy an opam switch";
  expect (has runtime "server.exe")
    "runtime image copies the native server binary";

  let fly = read_file (Filename.concat root "fly.toml") in
  expect
    (has fly "auto_stop_machines = \"suspend\"")
    "Fly idles machines with suspend";
  expect
    (has fly "auto_start_machines = true")
    "Fly autostarts stopped machines";
  expect (has fly "memory = \"256mb\"") "Fly VM memory stays at 256mb";
  expect (has fly "path = \"/health\"") "Fly HTTP check is GET /health";
  expect (has fly "min_machines_running = 0") "Fly does not keep a warm machine";

  let readme = read_file (Filename.concat root "README.md") in
  expect (has readme "v2026.08.30") "README names F* v2026.08.30";
  expect (has readme "OCaml 5.3") "README names OCaml 5.3";
  expect (not (has readme "CRaC")) "README does not claim a JVM CRaC runtime";
  expect
    (Sys.file_exists (Filename.concat root "AGENTS.md"))
    "AGENTS.md is committed";
  expect
    (Sys.file_exists (Filename.concat root "DECISIONS.md"))
    "DECISIONS.md is committed";
  expect
    (Sys.file_exists (Filename.concat root "MEMORY.md"))
    "MEMORY.md is committed";
  let agents = read_file (Filename.concat root "AGENTS.md") in
  expect (has agents "DECISIONS.md") "AGENTS.md points at DECISIONS.md";
  expect (has agents "MEMORY.md") "AGENTS.md points at MEMORY.md";

  let script = Filename.concat root "scripts/check-sbom.sh" in
  let opam = Filename.concat root "carolina_fstar.opam" in
  let sbom = Filename.concat root "opam-deps.cdx.json" in
  let code, out = run_capture [ script; opam; sbom ] in
  expect (code = 0) "committed SBOM lists every direct opam dependency";
  expect (has out "sbom includes") "SBOM gate reports the direct dependencies";
  expect
    (not (has (read_file sbom) "ocamlformat"))
    "optional ocamlformat stays out of the SBOM";

  let tmp = Filename.temp_dir "fstar-sbom" "" in
  Fun.protect
    ~finally:(fun () -> rm_r tmp)
    (fun () ->
      let omitted = Filename.concat tmp "omitted.cdx.json" in
      let kept = ref [] in
      List.iter
        (fun line ->
          if not (has line "\"name\": \"batteries\"") then kept := line :: !kept)
        (String.split_on_char '\n' (read_file sbom));
      write_file omitted (String.concat "\n" (List.rev !kept) ^ "\n");
      let code, out = run_capture [ script; opam; omitted ] in
      expect (code <> 0) "SBOM gate fails when a direct dependency is omitted";
      expect (has out "batteries")
        "SBOM gate names the omitted direct dependency";

      let extra = Filename.concat tmp "extra.opam" in
      let needle = "depends: [\n" in
      let src = read_file opam in
      let nlen = String.length needle in
      let rec find i =
        if i + nlen > String.length src then
          failwith "depends block not found in opam file"
        else if String.sub src i nlen = needle then
          String.sub src 0 (i + nlen)
          ^ "  \"not-a-real-direct-dep\"\n"
          ^ String.sub src (i + nlen) (String.length src - (i + nlen))
        else find (i + 1)
      in
      write_file extra (find 0);
      let code, out = run_capture [ script; extra; sbom ] in
      expect (code <> 0)
        "SBOM gate fails when opam names a dependency the SBOM lacks";
      expect
        (has out "not-a-real-direct-dep")
        "SBOM gate names the opam dependency missing from the SBOM")

let rec read_full fd buf off len =
  if len > 0 then
    let n = Unix.read fd buf off len in
    if n = 0 then failwith "stand-in eof"
    else read_full fd buf (off + n) (len - n)

let read_i32 fd =
  let b = Bytes.create 4 in
  read_full fd b 0 4;
  (Char.code (Bytes.get b 0) lsl 24)
  lor (Char.code (Bytes.get b 1) lsl 16)
  lor (Char.code (Bytes.get b 2) lsl 8)
  lor Char.code (Bytes.get b 3)

let add_i32 buf n =
  Buffer.add_char buf (Char.chr ((n lsr 24) land 255));
  Buffer.add_char buf (Char.chr ((n lsr 16) land 255));
  Buffer.add_char buf (Char.chr ((n lsr 8) land 255));
  Buffer.add_char buf (Char.chr (n land 255))

let send_all fd s =
  let b = Bytes.of_string s in
  let rec loop off =
    if off < Bytes.length b then
      let n = Unix.write fd b off (Bytes.length b - off) in
      if n = 0 then failwith "stand-in short write" else loop (off + n)
  in
  loop 0

let pg_ssl = 80877103
let pg_gss = 80877104
let pg_proto = 196608

let ready_for_query () =
  let buf = Buffer.create 128 in
  let add_msg tag payload =
    Buffer.add_char buf tag;
    add_i32 buf (4 + String.length payload);
    Buffer.add_string buf payload
  in
  let auth = Buffer.create 4 in
  add_i32 auth 0;
  add_msg 'R' (Buffer.contents auth);
  List.iter
    (fun (k, v) -> add_msg 'S' (k ^ "\000" ^ v ^ "\000"))
    [
      ("server_version", "14.0");
      ("client_encoding", "UTF8");
      ("server_encoding", "UTF8");
      ("DateStyle", "ISO, MDY");
      ("integer_datetimes", "on");
    ];
  add_msg 'Z' "I";
  Buffer.contents buf

let rec read_startup fd =
  let len = read_i32 fd in
  if len < 8 then failwith "short startup";
  let code = read_i32 fd in
  let rest = len - 8 in
  (if rest > 0 then
     let junk = Bytes.create rest in
     read_full fd junk 0 rest);
  if code = pg_ssl || code = pg_gss then (
    send_all fd "N";
    read_startup fd)
  else if code <> pg_proto then failwith ("startup code " ^ string_of_int code)

let read_message fd =
  let tagb = Bytes.create 1 in
  read_full fd tagb 0 1;
  let len = read_i32 fd in
  if len < 4 then failwith "short message";
  let n = len - 4 in
  (if n > 0 then
     let payload = Bytes.create n in
     read_full fd payload 0 n);
  Bytes.get tagb 0

(* Local stand-in for libpq. [Stall] accepts and never answers, so startup
   never completes. [QueryStall] finishes startup, reads one query, and then
   never answers. [Reset] completes startup, reads one query, and closes. *)
type pg_mode = Stall | QueryStall | Reset

let start_standin mode =
  let fd = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt fd Unix.SO_REUSEADDR true;
  Unix.bind fd (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  Unix.listen fd 16;
  let port =
    match Unix.getsockname fd with
    | Unix.ADDR_INET (_, p) -> p
    | Unix.ADDR_UNIX _ -> failwith "stand-in socket is not inet"
  in
  let accepts = ref 0 in
  let held = ref [] in
  let stop = ref false in
  (try Unix.setsockopt_float fd Unix.SO_RCVTIMEO 0.2 with _ -> ());
  let th =
    Thread.create
      (fun () ->
        while not !stop do
          match Unix.accept fd with
          | exception
              Unix.Unix_error
                ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) ->
              ()
          | exception _ -> stop := true
          | client, _ -> (
              incr accepts;
              match mode with
              | Stall -> held := client :: !held
              | QueryStall ->
                  ignore
                    (Thread.create
                       (fun () ->
                         try
                           Unix.setsockopt_float client Unix.SO_RCVTIMEO 3.0;
                           read_startup client;
                           send_all client (ready_for_query ());
                           ignore (read_message client);
                           held := client :: !held;
                           while not !stop do
                             Thread.delay 0.05
                           done
                         with _ -> ( try Unix.close client with _ -> ()))
                       ())
              | Reset -> (
                  (try
                     Unix.setsockopt_float client Unix.SO_RCVTIMEO 3.0;
                     read_startup client;
                     send_all client (ready_for_query ());
                     let tag = read_message client in
                     if tag <> 'Q' then
                       Printf.eprintf "stand-in: expected query, got %C\n%!" tag
                   with e ->
                     Printf.eprintf "stand-in: %s\n%!" (Printexc.to_string e));
                  try Unix.close client with _ -> ()))
        done)
      ()
  in
  (port, accepts, held, stop, fd, th)

let stop_standin held stop fd th =
  stop := true;
  List.iter
    (fun c ->
      (try Unix.shutdown c Unix.SHUTDOWN_ALL with _ -> ());
      try Unix.close c with _ -> ())
    !held;
  (try Unix.close fd with _ -> ());
  try Thread.join th with _ -> ()

let rec wait_until msg pred deadline =
  if pred () then ()
  else if Unix.gettimeofday () >= deadline then failwith msg
  else (
    Thread.delay 0.01;
    wait_until msg pred deadline)

let rec connect_loopback port spins =
  let fd = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  try
    Unix.connect fd (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
    fd
  with e ->
    (try Unix.close fd with _ -> ());
    if spins <= 0 then raise e;
    Thread.delay 0.01;
    connect_loopback port (spins - 1)

let rec write_bytes fd b off =
  if off < Bytes.length b then
    let n = Unix.write fd b off (Bytes.length b - off) in
    if n = 0 then failwith "http short write" else write_bytes fd b (off + n)

let rec read_http fd deadline acc =
  let remain = deadline -. Unix.gettimeofday () in
  if remain <= 0. then failwith "http client timeout"
  else
    match Unix.select [ fd ] [] [] remain with
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> read_http fd deadline acc
    | [], _, _ -> failwith "http client timeout"
    | _ -> (
        let buf = Bytes.create 4096 in
        match Unix.read fd buf 0 4096 with
        | exception Unix.Unix_error (Unix.EINTR, _, _) ->
            read_http fd deadline acc
        | 0 -> acc
        | n -> read_http fd deadline (acc ^ Bytes.sub_string buf 0 n))

let parse_http raw =
  let marker = "\r\n\r\n" in
  let m = String.length marker in
  let rec find i =
    if i + m > String.length raw then None
    else if String.sub raw i m = marker then Some i
    else find (i + 1)
  in
  match find 0 with
  | None -> (0, "")
  | Some i ->
      let head = String.sub raw 0 i in
      let body = String.sub raw (i + m) (String.length raw - i - m) in
      let status =
        match String.split_on_char ' ' head with
        | _ :: code :: _ -> ( try int_of_string code with _ -> 0)
        | _ -> 0
      in
      (status, body)

let http_get port path budget =
  let fd = connect_loopback port 50 in
  Fun.protect
    ~finally:(fun () -> try Unix.close fd with _ -> ())
    (fun () ->
      let req =
        Printf.sprintf
          "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" path
      in
      write_bytes fd (Bytes.of_string req) 0;
      parse_http (read_http fd (Unix.gettimeofday () +. budget) ""))

let is_json body =
  let n = String.length body in
  n >= 2 && body.[0] = '{' && body.[n - 1] = '}'

let with_database url f =
  let old = Sys.getenv_opt "DATABASE_URL" in
  Unix.putenv "DATABASE_URL" url;
  Catalog.disconnect ();
  Fun.protect
    ~finally:(fun () ->
      (try Catalog.disconnect () with _ -> ());
      match old with
      | Some s -> Unix.putenv "DATABASE_URL" s
      | None -> Unix.putenv "DATABASE_URL" "")
    f

let shipped_catalog sql args = Catalog.query sql args

let listen_tests () =
  (* Header-less peer: the shipped accept loop must still serve /health. *)
  let before_sql = !Catalog.sql_count in
  let before_acc = !Serve.accepted in
  let port = Serve.start shipped_catalog in
  let silent = connect_loopback port 50 in
  Fun.protect
    ~finally:(fun () -> try Unix.close silent with _ -> ())
    (fun () ->
      wait_until "silent client was not accepted"
        (fun () -> !Serve.accepted > before_acc)
        (Unix.gettimeofday () +. 2.0);
      let t0 = Unix.gettimeofday () in
      let status, body =
        try http_get port "/health" 3.0 with e -> (0, Printexc.to_string e)
      in
      let dt = Unix.gettimeofday () -. t0 in
      expect (status = 200) "headerless client: GET /health returns 200";
      expect (body = health_body)
        "headerless client: GET /health body is exactly {\"status\":\"ok\"}";
      expect (dt < 2.0)
        (Printf.sprintf
           "headerless client: GET /health returned in %.3fs (bound 2s)" dt);
      expect
        (!Catalog.sql_count = before_sql)
        "headerless client: GET /health does not query the catalog");

  (* Catalog call blocked inside libpq must not delay /health or query it. *)
  let pg_port, accepts, held, stop, pg_fd, pg_th = start_standin Stall in
  Fun.protect
    ~finally:(fun () -> stop_standin held stop pg_fd pg_th)
    (fun () ->
      let url =
        Printf.sprintf
          "postgres://postgres:postgres@127.0.0.1:%d/carolina_dev?connect_timeout=5"
          pg_port
      in
      with_database url (fun () ->
          let port = Serve.start shipped_catalog in
          let outcome = ref None in
          let t_req = Unix.gettimeofday () in
          let req =
            Thread.create
              (fun () ->
                outcome :=
                  Some
                    (try `Ok (http_get port "/v1/years" 3.0)
                     with e -> `Exn (Printexc.to_string e)))
              ()
          in
          wait_until "stalled catalog query did not reach the database"
            (fun () -> !accepts >= 1)
            (Unix.gettimeofday () +. 3.0);
          let sql_at_stall = !Catalog.sql_count in
          expect
            (sql_at_stall > before_sql)
            "stalled catalog query entered the catalog";
          expect (!outcome = None)
            "stalled catalog: request still in progress during health";
          let t0 = Unix.gettimeofday () in
          let status, body =
            try http_get port "/health" 3.0 with e -> (0, Printexc.to_string e)
          in
          let dt = Unix.gettimeofday () -. t0 in
          expect (status = 200) "stalled catalog: GET /health returns 200";
          expect (body = health_body)
            "stalled catalog: GET /health body is exactly {\"status\":\"ok\"}";
          expect (dt < 2.0)
            (Printf.sprintf
               "stalled catalog: GET /health returned in %.3fs (bound 2s)" dt);
          expect
            (!Catalog.sql_count = sql_at_stall)
            "stalled catalog: GET /health does not query the catalog";
          Thread.join req;
          let req_dt = Unix.gettimeofday () -. t_req in
          match !outcome with
          | Some (`Ok (st, resp)) ->
              expect
                (st >= 100 && st <= 599)
                (Printf.sprintf
                   "stalled catalog: catalog response has an HTTP status (got \
                    %d)"
                   st);
              expect (is_json resp)
                (Printf.sprintf
                   "stalled catalog: catalog response body is JSON (got %S)"
                   resp);
              expect (req_dt < 2.0)
                (Printf.sprintf
                   "stalled catalog: catalog JSON returned in %.3fs (bound 2s)"
                   req_dt)
          | Some (`Exn msg) ->
              expect false
                (Printf.sprintf "stalled catalog: catalog request failed: %s"
                   msg)
          | None ->
              expect false "stalled catalog: catalog request did not finish"));

  (* Startup succeeds, then the peer never answers the query. The catalog
     request must still finish with JSON, and /health must stay fast while
     that wait is in progress. *)
  let pg_port, accepts, held, stop, pg_fd, pg_th = start_standin QueryStall in
  Fun.protect
    ~finally:(fun () -> stop_standin held stop pg_fd pg_th)
    (fun () ->
      let url =
        Printf.sprintf "postgres://postgres:postgres@127.0.0.1:%d/carolina_dev"
          pg_port
      in
      with_database url (fun () ->
          let port = Serve.start shipped_catalog in
          let outcome = ref None in
          let t_req = Unix.gettimeofday () in
          let req =
            Thread.create
              (fun () ->
                outcome :=
                  Some
                    (try `Ok (http_get port "/v1/years" 3.0)
                     with e -> `Exn (Printexc.to_string e)))
              ()
          in
          wait_until "silent query did not reach the database"
            (fun () -> !accepts >= 1)
            (Unix.gettimeofday () +. 3.0);
          expect (!outcome = None)
            "silent query: request still in progress during health";
          let t0 = Unix.gettimeofday () in
          let status, body =
            try http_get port "/health" 3.0 with e -> (0, Printexc.to_string e)
          in
          let dt = Unix.gettimeofday () -. t0 in
          expect (status = 200) "silent query: GET /health returns 200";
          expect (body = health_body)
            "silent query: GET /health body is exactly {\"status\":\"ok\"}";
          expect (dt < 2.0)
            (Printf.sprintf
               "silent query: GET /health returned in %.3fs (bound 2s)" dt);
          Thread.join req;
          let req_dt = Unix.gettimeofday () -. t_req in
          (match !outcome with
          | Some (`Ok (st, resp)) ->
              expect
                (st >= 100 && st <= 599)
                (Printf.sprintf
                   "silent query: catalog response has an HTTP status (got %d)"
                   st);
              expect (is_json resp)
                (Printf.sprintf
                   "silent query: catalog response body is JSON (got %S)" resp);
              expect (req_dt < 2.0)
                (Printf.sprintf
                   "silent query: catalog JSON returned in %.3fs (bound 2s)"
                   req_dt)
          | Some (`Exn msg) ->
              expect false
                (Printf.sprintf "silent query: catalog request failed: %s" msg)
          | None -> expect false "silent query: catalog request did not finish");
          let connects_after = !Catalog.connect_count in
          let accepts_after = !accepts in
          let st2, body2 =
            try http_get port "/v1/years" 3.0
            with e -> (0, Printexc.to_string e)
          in
          expect
            (st2 >= 100 && st2 <= 599)
            (Printf.sprintf
               "silent query: following catalog response has an HTTP status \
                (got %d)"
               st2);
          expect (is_json body2)
            (Printf.sprintf
               "silent query: following catalog response body is JSON (got %S)"
               body2);
          expect
            (!Catalog.connect_count > connects_after)
            (Printf.sprintf
               "silent query: next catalog query opens a new database \
                connection (%d -> %d)"
               connects_after !Catalog.connect_count);
          expect (!accepts > accepts_after)
            (Printf.sprintf
               "silent query: next catalog query does not reuse the silent \
                connection (accepts %d -> %d)"
               accepts_after !accepts)));

  (* A query whose connection is closed must answer HTTP JSON, then connect again. *)
  let pg_port, accepts, held, stop, pg_fd, pg_th = start_standin Reset in
  Fun.protect
    ~finally:(fun () -> stop_standin held stop pg_fd pg_th)
    (fun () ->
      let url =
        Printf.sprintf "postgres://postgres:postgres@127.0.0.1:%d/carolina_dev"
          pg_port
      in
      with_database url (fun () ->
          let connects0 = !Catalog.connect_count in
          let port = Serve.start shipped_catalog in
          let status, body =
            try http_get port "/v1/years" 3.0
            with e -> (0, Printexc.to_string e)
          in
          expect
            (status >= 100 && status <= 599)
            (Printf.sprintf
               "reset database: catalog response has an HTTP status (got %d)"
               status);
          expect (is_json body)
            (Printf.sprintf
               "reset database: catalog response body is JSON (got %S)" body);
          let connects1 = !Catalog.connect_count in
          let accepts1 = !accepts in
          expect (connects1 > connects0)
            (Printf.sprintf
               "reset database: first catalog query opened a connection (%d -> \
                %d)"
               connects0 connects1);
          expect (accepts1 >= 1)
            "reset database: stand-in accepted the first catalog query";
          let status2, body2 =
            try http_get port "/v1/years" 3.0
            with e -> (0, Printexc.to_string e)
          in
          expect
            (status2 >= 100 && status2 <= 599)
            (Printf.sprintf
               "reset database: following catalog response has an HTTP status \
                (got %d)"
               status2);
          expect (is_json body2)
            (Printf.sprintf
               "reset database: following catalog response body is JSON (got \
                %S)"
               body2);
          expect
            (!Catalog.connect_count > connects1)
            (Printf.sprintf
               "reset database: next catalog query opens a new database \
                connection (%d -> %d)"
               connects1 !Catalog.connect_count);
          expect (!accepts > accepts1)
            (Printf.sprintf
               "reset database: next catalog query does not reuse the failed \
                connection (accepts %d -> %d)"
               accepts1 !accepts)));
  Printf.eprintf "listen tests passed\n%!"

let () =
  expect (Carolina.language = "F*") "identity language is F*";
  expect (Carolina.framework = "OCaml Unix") "framework is OCaml Unix";

  reset ();
  let s, b = call "/health" "" in
  expect_status s 200 "/health returns 200";
  expect (b = health_body) "/health body is exactly {\"status\":\"ok\"}";
  expect (!sqls = []) "/health does not query the catalog";

  reset ();
  let s, b = call "/health/" "" in
  expect_status s 200 "/health/ returns 200";
  expect (b = health_body) "/health/ body is exactly {\"status\":\"ok\"}";
  expect (!sqls = []) "/health/ does not query the catalog";

  reset ();
  let s, b = call "/" "" in
  expect_status s 200 "GET / returns 200";
  expect (has b {|"language":"F*"|}) "GET / contains \"language\":\"F*\"";
  expect
    (has b {|"framework":"OCaml Unix"|})
    "GET / contains \"framework\":\"OCaml Unix\"";
  expect (!sqls = []) "GET / does not query the catalog";

  reset ();
  let s, b = call "/v1/years" "" in
  expect_status s 200 "/v1/years returns 200";
  expect_data b "/v1/years payload is data";
  expect (has b "2026") "/v1/years includes the year row";

  reset ();
  let s, b = call "/v1/speakers" "" in
  expect_status s 200 "/v1/speakers returns 200";
  expect_data b "/v1/speakers payload is data";
  expect (has b "diana-pham") "/v1/speakers includes the speaker";

  reset ();
  let s, b = call "/v1/speakers" "2026" in
  expect_status s 200 "year-scoped speakers return 200";
  expect_data b "year-scoped speakers payload is data";
  expect (has b "\"talks\"") "year-scoped speakers include talks";
  expect (has b "\"languages\"") "year-scoped speakers include languages";
  expect (has b "\"topics\"") "year-scoped speakers include topics";
  expect (has b "php") "year-scoped speaker languages include php";
  expect (has b "development") "year-scoped speaker topics include development";
  expect (queried "v1_talks") "year-scoped speakers query v1_talks";
  expect
    (not (queried "v1_year_speakers"))
    "year-scoped speakers do not query v1_year_speakers";

  reset ();
  let s, b = call "/v1/speakers/diana-pham" "" in
  expect_status s 200 "/v1/speakers/:slug returns 200";
  expect_data b "/v1/speakers/:slug payload is data";
  expect (has b "diana-pham") "/v1/speakers/:slug includes the speaker";
  expect (has b "\"talks\"") "/v1/speakers/:slug includes talks";
  expect (has b "\"years\"") "/v1/speakers/:slug includes years";

  reset ();
  let s, b = call "/v1/speakers/no-such-slug" "" in
  expect_status s 404 "missing /v1/speakers/:slug returns 404";
  expect (b = not_found_body) "missing speaker body is not_found";

  reset ();
  let s, b = call "/v1/speakers/2026/diana-pham" "" in
  expect_status s 200 "/v1/speakers/:year/:slug returns 200";
  expect_data b "/v1/speakers/:year/:slug payload is data";
  expect (has b "\"talks\"") "year-scoped speaker detail includes talks";
  expect (has b "\"languages\"") "year-scoped speaker detail includes languages";
  expect (has b "\"topics\"") "year-scoped speaker detail includes topics";
  expect (has b "\"years\"") "year-scoped speaker detail includes years";
  expect (has b "\"other_years\"")
    "year-scoped speaker detail includes other_years";
  expect (has b "2025") "year-scoped speaker other_years includes 2025";
  expect (queried "v1_talks") "year-scoped speaker detail queries v1_talks";
  expect
    (not (queried "v1_year_speakers"))
    "year-scoped speaker detail does not query v1_year_speakers";

  reset ();
  let s, b = call "/v1/speakers/1999/diana-pham" "" in
  expect_status s 404 "speaker with no talks in that year returns 404";
  expect (b = not_found_body) "speaker year miss body is not_found";

  reset ();
  let s, b = call "/v1/speakers/2026/no-such-slug" "" in
  expect_status s 404 "missing year-scoped speaker returns 404";
  expect (b = not_found_body) "missing year-scoped speaker body is not_found";

  reset ();
  let s, b = call "/v1/sponsors" "" in
  expect_status s 200 "/v1/sponsors returns 200";
  expect_data b "/v1/sponsors payload is data";
  expect (has b "flywheel") "/v1/sponsors includes the sponsor";

  reset ();
  let s, b = call "/v1/sponsors" "2026" in
  expect_status s 200 "year-scoped sponsors return 200";
  expect_data b "year-scoped sponsors payload is data";
  expect (has b "\"tier\"") "year-scoped sponsors include tier";
  expect (has b "platinum") "year-scoped sponsor tier is platinum";

  reset ();
  let s, b = call "/v1/sponsors/flywheel" "" in
  expect_status s 200 "/v1/sponsors/:slug returns 200";
  expect_data b "/v1/sponsors/:slug payload is data";
  expect (has b "\"sponsorships\"") "sponsor detail includes sponsorships";
  expect (has b "flywheel") "sponsor detail includes the sponsor";

  reset ();
  let s, b = call "/v1/sponsors/missing-sponsor" "" in
  expect_status s 404 "missing /v1/sponsors/:slug returns 404";
  expect (b = not_found_body) "missing sponsor body is not_found";

  reset ();
  let s, b = call "/v1/sponsors/2026/flywheel" "" in
  expect_status s 200 "/v1/sponsors/:year/:slug returns 200";
  expect_data b "/v1/sponsors/:year/:slug payload is data";
  expect (has b "\"tier\"") "year-scoped sponsor detail includes tier";
  expect (has b "platinum") "year-scoped sponsor detail tier is platinum";
  expect (has b "\"years\"") "year-scoped sponsor detail includes years";
  expect (has b "\"other_years\"")
    "year-scoped sponsor detail includes other_years";
  expect (has b "2025") "year-scoped sponsor other_years includes 2025";

  reset ();
  let s, b = call "/v1/sponsors/2026/missing-sponsor" "" in
  expect_status s 404 "missing year-scoped sponsor returns 404";
  expect (b = not_found_body) "missing year-scoped sponsor body is not_found";

  reset ();
  let s, b = call "/v1/sponsors/1999/flywheel" "" in
  expect_status s 404 "sponsor absent from that year returns 404";
  expect (b = not_found_body) "sponsor year miss body is not_found";

  reset ();
  let s, b = call "/not-a-route" "" in
  expect_status s 404 "unknown path returns 404";
  expect (b = not_found_body) "unknown path body is not_found";
  expect (!sqls = []) "unknown path does not query the catalog";

  Printf.eprintf "handler tests passed\n%!";
  gate_tests ();
  ci_shape_tests ();
  listen_tests ();

  if !failed > 0 then (
    Printf.eprintf "tests failed (%d)\n%!" !failed;
    exit 1);
  Printf.eprintf "all tests passed\n%!";
  exit 0
