{ stdenv }:
let

  baseNameOfDropExt = p:
    builtins.head ( builtins.split "[-.]" ( baseNameOf ( toString p ) ) );
  objName = file: ( baseNameOfDropExt file ) + ".o";
  objNames = sources: builtins.concatStringsSep " " ( map objName sources );

  # Fixup flags that weren't properly split on spaces.
  splitFlags' = f: builtins.filter builtins.isString ( builtins.split " " f );
  splitFlags = fs: builtins.concatMap splitFlags' fs;

in rec {

  ccDebugFlags = ["-O0" "-ggdb"];
  ccProdFlags  = ["-O2"];

  mkArchive = name: files: derivation {
    inherit name files;
    inherit (stdenv) system;
    builder = "${stdenv.cc.bintools.bintools_bin}/bin/ar";
    args = ["crs" ( builtins.placeholder "out" )] ++ ( map toString files );
  };

  compileCxx = flags: file: derivation {
    name = if ( builtins.isString file ) then objName file else "cxx-obj.o";
    inherit (stdenv) system;
    inherit flags file;
    builder = "${stdenv.cc}/bin/g++";
    args = [
      "-c" ( toString file )
      "-o" ( builtins.placeholder "out" )
    ] ++ ( splitFlags flags );
  };

  compileCxxArchive = name: flags: files:
    mkArchive name ( map ( compileCxx flags ) files );

  compileCxxStaticArchive = name: flags: files:
    compileCxxArchive name ( flags ++ ["-static"] ) files;

  compileCxxPicArchive = name: flags: files:
    compileCxxArchive name ( flags ++ ["-shared" "-fPIC"] ) files;

}
