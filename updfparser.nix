{ stdenv, src, support }:
let
  archives = support.mkCxxArchives { name = "libupdfparser"; inherit src; };
in {
  inherit archives;
  source = support.sourceDrv "updfparser-source" src;
}
