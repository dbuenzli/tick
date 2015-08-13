#!/usr/bin/env ocaml
#directory "pkg";;
#use "topkg.ml";;

let () =
  Pkg.describe "tick" ~builder:`OCamlbuild [
    Pkg.lib "pkg/META";
    Pkg.doc "README.md";
    Pkg.doc "CHANGES.md"; ]
