{ stdenv , src , support ? import ./support.nix { inherit stdenv; } }:
let
  inherit (support) compileCxxStaticArchive compileCxxPicArchive;
  inherit (support) ccProdFlags ccDebugFlags;
  includes    = [( src + "/include" )];
  sources     = map ( p: src + "/src/" + p ) ["uPDFParser.cpp" "uPDFTypes.cpp"];
  incFlags    = map ( p: "-I" + p ) includes;
  cxxFlags    = incFlags ++ ccProdFlags;
  cxxDbgFlags = incFlags ++ ccDebugFlags;
in {
  static = compileCxxStaticArchive "libupdfparser.a" cxxFlags sources;
  pic = compileCxxPicArchive "libupdfparser.pic.a" cxxFlags sources;
  static-dbg = compileCxxStaticArchive "libupdfparser-dbg.a" cxxDbgFlags sources;
  pic-dbg = compileCxxPicArchive "libupdfparser-dbg.pic.a" cxxDbgFlags sources;
}
