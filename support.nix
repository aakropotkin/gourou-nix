{ stdenv }:
let

  baseNameOfDropExt = p:
    builtins.head ( builtins.split "." ( baseNameOf ( toString p ) ) );
  objName = file: ( baseNameOfDropExt file ) + ".o";
  objNames = sources: builtins.concatStringsSep " " ( map objName sources );

  # Fixup flags that weren't properly split on spaces.
  splitFlags' = f: builtins.filter builtins.isString ( builtins.split " " f );
  splitFlags = fs: builtins.concatMap splitFlags' fs;

in rec {

  mkArchive = name: files: derivation {
    inherit name files;
    inherit (stdenv) system;
    builder = "${stdenv.cc.bintools.bintools_bin}/bin/ar";
    args = ["crs" ( builtins.placeholder "out" )] ++ [files];
  };

  compileCxx = flags: file: derivation {
    name = objName file;
    inherit flags file;
    inherit (stdenv) system;
    builder = "${stdenv.cc}/bin/g++";
    args = [
      "-o" ( builtins.placeholder "out" )
      "-c" file
    ] ++ ( splitFlags flags );
  };

  compileCxxArchive = name: flags: files:
    mkArchive name ( map ( compileCxx flags ) files );

  compileCxxStaticArchive = name: flags: files:
    compileCxxArchive name ( flags ++ ["-static"] ) files;

  compileCxxPicArchive = name: flags: files:
    compileCxxArchive name ( flags ++ ["-shared" "-fPIC"] ) files;

}
