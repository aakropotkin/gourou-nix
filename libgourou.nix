{ stdenv
, src
, openssl
, libzip
, curl
, updfparser
, base64
, pugixml
, enableStatic ? false
, enableDebug  ? false
, disableWall  ? false
}:
let
# From `pugixml' we only need `pugixml.[ch]pp', and `pugiconfig.hpp'

# g++ obj/*.o ./lib/updfparser/libupdfparser.a -o libgourou.so -shared
# g++ $CXX_FLAGS acsmdownloader.cpp utils.a -L/data/repos/libgourou -lcrypto  \
#     -lzip -lz -lcurl -lgourou -o acsmdownloader
in stdenv.mkDerivation rec {
  pname = "libgourou";
  version = "0.7.1";
  src = builtins.filterSource ( name: type:
    let
      inherit (builtins) elem;
      bname = baseNameOf name;
      dirBname = baseNameOf ( dirOf name );
      keepDirs = ["include" "src"];
    in
    ( ( type == "directory" ) && ( elem bname keepDirs ) ) ||
    ( ( type == "regular" ) && ( elem dirBname keepDirs ) )
  ) src;
  SOURCES = [
    "./src/libgourou.cpp"
    "./src/user.cpp"
    "./src/device.cpp"
    "./src/fulfillment_item.cpp"
    "./src/loan_token.cpp"
    "./src/bytearray.cpp"
    "${pugixml}/src/pugixml.cpp"
  ];
  enableStatic = true;
  enableDebug  = false;
  disableWall  = false;
  CXXFLAGS = [
    "-I./include"
    "-I${pugixml}/src"
    "-I${updfparser.dev}/include"
  ] ++ ( if enableDebug then ["-O0 -ggdb"] else ["-O2"] )
    ++ ( if disableWall then [] else ["-Wall"] )
    ++ ( if enableStatic then ["-static"] else ["-fPIC -shared"] );
  # Executables link: -lcrypto -lzip -lz -lcurl -lgourou
  LDFLAGS = if enableStatic then [
    "-static"
  ] else [
    "-shared"
  ];
  UPDFPARSERLIB =
    if enableStatic then "${updfparser.dev}/lib/libupdfparser.a"
                    else "${updfparser}/lib/libupdfparser.so";
  buildInputs = [
    openssl.dev
    libzip.dev
    curl.dev
  ];
  buildPhase = builtins.concatStringsSep "\n" (
    ["runHook preBuild"] ++
    ( map ( s: "g++ $CXXFLAGS -c ${s}" ) SOURCES ) ++ [
      ( "ar crs libgourou.a ${objNames SOURCES}" + (
        if enableStatic then ( " " + UPDFPARSERLIB ) else "" ) )
      "runHook postBuild"
    ] ++ ( if enableStatic then [] else [
      "g++ $LDFLAGS ./libgourou.a $UPDFPARSERLIB -o libgourou.so -Wl,--no-whole-archive -Wl,--as-needed"
    ] ) );
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    cp -p --reflink=auto -- ./libgourou.${if enableStatic then "a" else "so"} $out/lib
    cp -pr --reflink=auto -- ./include $out/
    runHook postInstall
  '';
  dontFixup = true;
}
