{ stdenv, linkFarmFromDrvs }:
let

  baseName = p: with builtins;
    let
      bp = baseNameOf ( toString p );
      isBaseName = mb: ( baseNameOf mb ) == mb;
      isNixStorePath = nsp:
        let prefix = "/nix/store/"; plen = stringLength prefix; in
        prefix == ( substring 0 plen ( toString nsp ) );
      removeNixStorePrefix = nsp:
        let m = match "/nix/store/[^-]+-(.*)" ( toString nsp ); in
        if m == null then nsp else ( head m );
    in baseNameOf ( removeNixStorePrefix ( p ) );
  baseName' = p: builtins.unsafeDiscardStringContext ( baseName p );

  baseNameOfDropExt = p: builtins.head ( builtins.split "\\." ( baseName' p ) );
  objName = file: ( baseNameOfDropExt file ) + ".o";
  objNames = sources: builtins.concatStringsSep " " ( map objName sources );


/* -------------------------------------------------------------------------- */

  # Fixup flags that weren't properly split on spaces.
  splitFlags' = f: builtins.filter builtins.isString ( builtins.split " " f );
  splitFlags = fs: builtins.concatMap splitFlags' fs;

  fixupWlPrefix = s:
    if ( ( builtins.substring 0 4 s ) != "-Wl," ) then ( "-Wl," + s ) else s;
  fixupLdFlag = flag: with builtins;
    let cms = s: concatStringsSep "," ( filter isString ( split " +" s ) );
    in fixupWlPrefix ( cms ( toString flag ) );


/* -------------------------------------------------------------------------- */

  listFiles = dir:
    let
      inherit (builtins) readDir attrValues mapAttrs filter;
      process = name: type: let bname = baseNameOf name; in
        if ( type == "directory" ) then null
                                   else ( ( toString dir ) + "/" + bname );
      files = attrValues ( mapAttrs process ( readDir dir ) );
    in filter ( x: x != null ) files;


/* -------------------------------------------------------------------------- */

  findFileWithSuffix = dir: sfx:
    let
      fs = builtins.readDir dir;
      slen = builtins.stringLength sfx;
      suffstring = l: str: let sl = builtins.stringLength str; in
        builtins.substring ( sl - l ) sl str;
      hasSfx = s: ( suffstring slen s ) == sfx;
      matches = builtins.filter hasSfx ( builtins.attrNames fs );
    in ( toString dir ) + "/" + ( builtins.head matches );


/* -------------------------------------------------------------------------- */

  cxxBin = findFileWithSuffix "${stdenv.cc}/bin" "g++";
  arBin  = findFileWithSuffix "${stdenv.cc.bintools.bintools_bin}/bin" "ar";


/* -------------------------------------------------------------------------- */

in rec {

  inherit linkFarmFromDrvs stdenv listFiles;

  ccDebugFlags = ["-O0" "-ggdb"];
  ccOptFlags  = ["-O2"];


/* -------------------------------------------------------------------------- */

  compileCxx = flags: file: derivation {
    name = objName file;
    inherit (stdenv) system;
    inherit flags file;
    builder = cxxBin;
    args = [
      "-c" ( toString file )
      "-o" ( builtins.placeholder "out" )
    ] ++ ( splitFlags flags );
    preferLocalBuild = true;
  };


/* -------------------------------------------------------------------------- */

  linkCxxExecutable = {
    name
  , files  # Must define `main'
  # Passed to the CXX compiler.
  # These are commonly flags like `-shared', `-f<...>', `-L<PATH>, or `-l<LIB>'.
  , earlyCxxLinkFlags   ? []  # Added before PIC archive.
  , defaultCxxLinkFlags ? []  # Added before PIC archive.
  , cxxLinkFlags        ? []  # Added after PIC archive.

  # Passed through to link-editor by CXX compiler.
  # `-Wl,<FLAG>' is added if missing, and spaces will be replaced by commas
  # rather than split into separate arguments.
  , earlyLdFlags   ? []
  , defaultLdFlags ? []
  , ldFlags        ? []
  }:
  let
    earlyCxxLinkFlags'   = splitFlags earlyCxxLinkFlags;
    defaultCxxLinkFlags' = splitFlags defaultCxxLinkFlags;
    cxxLinkFlags'        = splitFlags cxxLinkFlags;
    earlyLdFlags'   = map fixupLdFlag earlyLdFlags;
    defaultLdFlags' = map fixupLdFlag defaultLdFlags;
    ldFlags'        = map fixupLdFlag ldFlags;
  in derivation {
    inherit (stdenv) system;
    inherit name files;
    inherit earlyCxxLinkFlags earlyLdFlags;
    inherit defaultCxxLinkFlags defaultLdFlags;
    inherit cxxLinkFlags ldFlags;
    builder = cxxBin;
    args = earlyCxxLinkFlags' ++ earlyLdFlags' ++
           defaultCxxLinkFlags' ++ defaultLdFlags' ++
           ["-o" ( builtins.placeholder "out" )] ++
           ( map toString files )
           ++ cxxLinkFlags' ++ ldFlags';
  };


/* -------------------------------------------------------------------------- */

  mkArchive = name: files: derivation {
    inherit name files;
    inherit (stdenv) system;
    builder = arBin;
    args = ["crs" ( builtins.placeholder "out" )] ++ ( map toString files );
    preferLocalBuild = true;
  };


/* -------------------------------------------------------------------------- */

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

/* -------------------------------------------------------------------------- */

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
    preferLocalBuild = true;
  };


/* -------------------------------------------------------------------------- */

  # FIXME: ".so" assumes ELF libraries on Linux, Darwin will shit the bed here.
  # Flag ordering is:
  #   CXX ${earlyCxxLinkFlags}   ${earlyLdFlags}    \
  #       ${defaultCxxLinkFlags} ${defaultLdFlags}  \
  #       -Wl,--push-state,--whole-archive          \
  #       ${picArchive} -Wl,--pop-state             \
  #       ${cxxLinkFlags} ${ldFlags}                \
  #       -o $out
  cxxSharedLibraryFromArchive = {
    name       ? ( baseNameOfDropExt picArchive.name ) + ".so"
  , soname     ? name
  , picArchive

  # Passed to the CXX compiler.
  # These are commonly flags like `-shared', `-f<...>', `-L<PATH>, or `-l<LIB>'.
  , earlyCxxLinkFlags   ? []           # Added before PIC archive.
  , defaultCxxLinkFlags ? ["-shared"]  # Added before PIC archive.
  , cxxLinkFlags        ? []           # Added after PIC archive.

  # Passed through to link-editor by CXX compiler.
  # `-Wl,<FLAG>' is added if missing, and spaces will be replaced by commas
  # rather than split into separate arguments.
  , earlyLdFlags   ? []
  , defaultLdFlags ? ["-Wl,-soname,${soname}"]
  , ldFlags        ? ["-Wl,-z,defs,--no-allow-shlib-undefined"]
  }:
  let
    earlyCxxLinkFlags'   = splitFlags earlyCxxLinkFlags;
    defaultCxxLinkFlags' = splitFlags defaultCxxLinkFlags;
    cxxLinkFlags'        = splitFlags cxxLinkFlags;
    earlyLdFlags'   = map fixupLdFlag earlyLdFlags;
    defaultLdFlags' = map fixupLdFlag defaultLdFlags;
    ldFlags'        = map fixupLdFlag ldFlags;
  in derivation {
    inherit name soname picArchive;
    inherit (stdenv) system;
    builder = cxxBin;
    args = earlyCxxLinkFlags' ++ earlyLdFlags' ++
           defaultCxxLinkFlags' ++ defaultLdFlags' ++ [
             "-o" ( builtins.placeholder "out" )
             "-Wl,--push-state,--whole-archive"
             ( toString picArchive )
             "-Wl,--pop-state"
           ] ++ cxxLinkFlags' ++ ldFlags';
  };

  cxxSharedLibsFromArchives = {
    name ? ( baseNameOfDropExt optPicArchive.name )
  , optPicArchive
  , dbgPicArchive

  , commonArgs     ? { soname = name + ".so"; }
  , optArgOverride ? ( prev: {} )
  , dbgArgOverride ? ( prev: {} )

  , defaultOptArgOverride ? ( prev: {
      name = name + ".so";
      picArchive = optPicArchive;
  } )
  , defaultDbgArgOverride ? ( prev: {
      name = name + ".dbg.so";
      picArchive = dbgPicArchive;
    } )
  }:
  let
    composeOvs = builtins.foldl' ( a: o: a // ( o a ) );
    optArgs = composeOvs commonArgs [defaultOptArgOverride optArgOverride];
    dbgArgs = composeOvs commonArgs [defaultDbgArgOverride dbgArgOverride];

    opt = cxxSharedLibraryFromArchive optArgs;
    dbg = cxxSharedLibraryFromArchive dbgArgs;
  in {
    inherit opt dbg;
    all = linkFarmFromDrvs name [opt dbg];
  };


/* -------------------------------------------------------------------------- */

  mkLibOverride = libs: flavor:
    let shLibs = if ( libs ? sharedLibs ) then libs.sharedLibs else libs;
    in prev: {
      cxxLinkFlags = ( prev.cxxLinkFlags or [] ) ++ [shLibs.${flavor}.outPath];
    };


/* -------------------------------------------------------------------------- */

  mkCxxLibs = args@{ name, src, ... }:
    let
      inherit (builtins) intersectAttrs functionArgs;
      aflags = intersectAttrs ( functionArgs mkCxxArchives ) args;
      archives = mkCxxArchives aflags;
      sflags = intersectAttrs ( functionArgs cxxSharedLibsFromArchives ) args;
      sharedLibs = cxxSharedLibsFromArchives ( sflags // {
        optPicArchive = archives.opt.pic;
        dbgPicArchive = archives.dbg.pic;
      } );
    in {
      inherit archives sharedLibs;
      all = linkFarmFromDrvs ( name + "-lib" ) [
        archives.opt.static archives.opt.pic sharedLibs.opt
        archives.dbg.static archives.dbg.pic sharedLibs.dbg
      ];
    };


/* -------------------------------------------------------------------------- */

  mkBinLink = name: path: derivation {
    inherit name;
    inherit (stdenv) system;
    builder = "${stdenv.shell}";
    PATH = "${stdenv.cc.coreutils_bin}/bin";
    args = ["-c" ''mkdir -p "$out"; ln -s ${path} "$out/bin"''];
    preferLocalBuild = true;
    allowSubstitutes = false;
  };

  mkBinDir = name: bins:
    mkBinLink name ( linkFarmFromDrvs ( name + "-bins" ) bins );


/* -------------------------------------------------------------------------- */

}
