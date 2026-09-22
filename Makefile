FSTAR_HOME ?= $(HOME)/.local/opt/fstar
FSTAR ?= $(FSTAR_HOME)/bin/fstar.exe
APP_ML ?= $(FSTAR_HOME)/lib/fstar/lib/app
export PATH := $(HOME)/.local/bin:$(HOME)/.opam/5.3.0/bin:$(HOME)/.local/share/mise/installs/gitleaks/8.30.1:$(FSTAR_HOME)/bin:$(PATH)

OPAM_ENV = opam env --switch=5.3.0 2>/dev/null || opam env

# Handwritten OCaml only. Generated F* extraction is not a formatting surface.
HANDWRITTEN_ML := ocaml/catalog.ml ocaml/server.ml ocaml/test.ml

# Semgrep CE on shipped F* / handwritten OCaml / libpq stubs (not _build/).
SAST_PATHS := src ocaml/catalog.ml ocaml/server.ml ocaml/test.ml ocaml/pq_stubs.c

.PHONY: extract runtime build release test run fmt fmt-check sast vuln audit secrets check ci hooks

extract:
	mkdir -p ocaml-output
	$(FSTAR) --cache_off --codegen OCaml --extract Carolina --odir ocaml-output src/Carolina.fst
	cp ocaml-output/Carolina.ml ocaml/Carolina.ml

runtime:
	cp $(APP_ML)/Prims.ml ocaml/Prims.ml
	cp $(APP_ML)/FStar_Char.ml ocaml/FStar_Char.ml
	cp $(APP_ML)/FStar_String.ml ocaml/FStar_String.ml
	cp $(APP_ML)/FStar_List_Tot_Base.ml ocaml/FStar_List_Tot_Base.ml
	cp $(APP_ML)/ints/FStar_UInt32.ml ocaml/FStar_UInt32.ml

build: extract runtime
	eval $$($(OPAM_ENV)) && dune build

release: extract runtime
	eval $$($(OPAM_ENV)) && dune build --profile release

test: build
	eval $$($(OPAM_ENV)) && dune exec ./ocaml/test.exe

run: build
	eval $$($(OPAM_ENV)) && dune exec ./ocaml/server.exe

fmt:
	eval $$($(OPAM_ENV)) && ocamlformat -i $(HANDWRITTEN_ML)

fmt-check:
	eval $$($(OPAM_ENV)) && ocamlformat --check $(HANDWRITTEN_ML)

sast:
	semgrep --error --metrics=off --disable-version-check --config .semgrep.yml $(SAST_PATHS)

vuln:
	sh scripts/check-sbom.sh carolina_fstar.opam opam-deps.cdx.json
	osv-scanner scan source --config=osv-scanner.toml -L opam-deps.cdx.json

audit: vuln

secrets:
	gitleaks dir --no-banner -v .

check: test sast vuln secrets fmt-check

ci: check

hooks:
	pre-commit install
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit
