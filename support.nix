{ stdenv, linkFarmFromDrvs }:
let

  baseName' = p: with builtins;
    if ( isPath p ) then ( baseNameOf p ) else
      if ( isString p ) then
        ( if ( hasContext p ) then ( head ( match "[^-]*-(.*)" p ) )
                              else ( baseNameOf p ) )
      else throw "Cannot take basename of type: ${typeOf p}";

  baseNameOfDropExt = p: builtins.head ( builtins.split "." ( baseName' p ) );
  objName = file: ( baseNameOfDropExt file ) + ".o";
  objNames = sources: builtins.concatStringsSep " " ( map objName sources );

  # Fixup flags that weren't properly split on spaces.
  splitFlags' = f: builtins.filter builtins.isString ( builtins.split " " f );
  splitFlags = fs: builtins.concatMap splitFlags' fs;

  listFiles = dir:
    let
      inherit (builtins) readDir attrValues mapAttrs filter;
      process = name: type: let bname = baseNameOf name; in
        if ( type == "directory" ) then null
                                   else ( ( toString dir ) + "/" + bname );
      files = attrValues ( mapAttrs process ( readDir dir ) );
    in filter ( x: x != null ) files;

in rec {

  ccDebugFlags = ["-O0" "-ggdb"];
  ccOptFlags  = ["-O2"];

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

  mkCxxArchives = {
    name
  , src      ? null
  , includes ? [( src + "/include" )]
  , flags    ? []
  , files    ? listFiles ( src + "/src" )
  }:
  let
    incFlags = map ( p: "-I" + p ) includes;
    flags' = ( splitFlags flags ) ++ incFlags;
    mkFlavor = suffix: fflags:
      let
        staticName = name + suffix + ".a";
        picName    = name + suffix + ".pic.a";
    in {
      static = compileCxxStaticArchive staticName ( flags' ++ fflags ) files;
      pic = compileCxxPicArchive picName ( flags' ++ fflags ) files;
    };
    opt = mkFlavor "" ccOptFlags;
    dbg = mkFlavor ".dbg" ccDebugFlags;
  in {
    inherit opt dbg;
    all = linkFarmFromDrvs ( name + "-lib-archives" )
                           [opt.static opt.pic dbg.static dbg.pic];
  };

  sourceDrv = name: src: derivation {
    inherit name;
    inherit (stdenv) system;
    builder = "${stdenv.cc.coreutils_bin}/bin/cp";
    args = [
      "-pr"
      "--reflink=auto"
      "--"
      ( toString src )
      ( builtins.placeholder "out" )
    ];
  };

}
