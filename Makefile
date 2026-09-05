FSTAR_HOME ?= $(HOME)/.local/opt/fstar
FSTAR ?= $(FSTAR_HOME)/bin/fstar.exe
APP_ML ?= $(FSTAR_HOME)/lib/fstar/lib/app
export PATH := $(HOME)/.local/bin:$(FSTAR_HOME)/bin:$(PATH)

.PHONY: extract runtime build test run

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
	eval $$(opam env --switch=5.3.0) && dune build

test: build
	eval $$(opam env --switch=5.3.0) && dune exec ./ocaml/test.exe

run: build
	eval $$(opam env --switch=5.3.0) && dune exec ./ocaml/server.exe
