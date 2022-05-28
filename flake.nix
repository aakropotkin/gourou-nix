{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils/master";
    gourou-src = {
      #url   = "github:BentonEdmondson/the-scroll/main";
      url   = "git://soutade.fr/libgourou.git";
      type  = "git";
      ref   = "master";
      flake = false;
    };
    updfparser-src = {
      url   = "git://soutade.fr/updfparser.git";
      type  = "git";
      ref   = "master";
      flake = false;
    };
    base64-src = {
      url = "git+https://gist.github.com/f0fd86b6c73063283afe550bc5d77594.git";
      flake = false;
    };
    pugixml-src = {
      url   = "github:zeux/pugixml/latest";
      flake = false;
    };
  };

  outputs =
    { self
    , nixpkgs
    , utils
    , gourou-src
    , updfparser-src
    , base64-src
    , pugixml-src
    }:
    let
      supportedSystems = ["x86_64-linux"];
      systemsMap = utils.lib.eachSystemMap supportedSystems;
    in {
      packages = systemsMap ( system:
        let
          pkgsFor = import nixpkgs { inherit system; };
          # From `pugixml' we only need `pugixml.[ch]pp', and `pugiconfig.hpp'
          UPDFPARSERLIB = [
            # You do actually have to build this.
            # It's linked using an absolute path, not `-l<LIB>', as a static
            # library embedded into `libgourou.a', which is then used to
            # create `libgourou.so'.
          ];
          # NOTE: No libraries are linked here.
          # g++ obj/*.o ./lib/updfparser/libupdfparser.a -o libgourou.so -shared
          #
          # NOTE: Libraries get linked for the executables though
          # g++ $CXX_FLAGS acsmdownloader.cpp utils.a -L/data/repos/libgourou -lcrypto -lzip -lz -lcurl -lgourou -o acsmdownloader
          # g++ $CXX_FLAGS adept_activate.cpp utils.a -L/data/repos/libgourou -lcrypto -lzip -lz -lcurl -lgourou -o adept_activate
          # g++ $CXX_FLAGS adept_remove.cpp utils.a -L/data/repos/libgourou -lcrypto -lzip -lz -lcurl -lgourou -o adept_remove
          # g++ $CXX_FLAGS adept_loan_mgt.cpp utils.a -L/data/repos/libgourou -lcrypto -lzip -lz -lcurl -lgourou -o adept_loan_mgt

          CXXFLAGS_DEBUG = ["-O0" "-ggdb"];
          CXXFLAGS_PROD  = ["-O2"];

          inherit (builtins) concatStringsSep;

        in rec {
          base64 = import ./base64.nix {
            inherit system;
            inherit (pkgsFor) bash coreutils;
            src = base64-src;
          };

          updfparser = import ./updfparser.nix {
            inherit (pkgsFor) stdenv;
            src = updfparser-src;
          };

          libgourou = pkgsFor.stdenv.mkDerivation rec {
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
            ) gourou-src;
            SOURCES = [
              "./src/libgourou.cpp"
              "./src/user.cpp"
              "./src/device.cpp"
              "./src/fulfillment_item.cpp"
              "./src/loan_token.cpp"
              "./src/bytearray.cpp"
              "${pugixml-src}/src/pugixml.cpp"
            ];
            enableStatic = true;
            enableDebug  = false;
            disableWall  = false;
            CXXFLAGS = [
              "-I./include"
              "-I${pugixml-src}/src"
              "-I${updfparser-src}/include"
            ] ++ ( if enableDebug then CXXFLAGS_PROD else CXXFLAGS_DEBUG )
              ++ ( if disableWall then [] else ["-Wall"] )
              ++ ( if enableStatic then ["-static"] else ["-fPIC -shared"] );
            # Executables link: -lcrypto -lzip -lz -lcurl -lgourou
            LDFLAGS = if enableStatic then [
              "-static"
              "-Wl,-Bstatic"
            ] else [
              "-shared"
              "-Wl,--whole-archive"
            ];
            UPDFPARSERLIB =
              if enableStatic then "${updfparser.dev}/lib/libupdfparser.a"
                              else "${updfparser}/lib/libupdfparser.so";
            buildInputs = [
              pkgsFor.openssl.dev
              pkgsFor.libzip.dev
              pkgsFor.curl.dev
            ];
            patchPhase = ''
              runHook prePatch
              mkdir -p ./include
              cp -pr --reflink=auto -- ${base64-src} ./include/base64
              runHook postPatch
            '';
            buildPhase = concatStringsSep "\n" (
              ["runHook preBuild"] ++
              ( map ( s: "g++ $CXXFLAGS -c ${s}" ) SOURCES ) ++ [
                ( "ar crs libgourou.a *.o" + (
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
          };
          default = libgourou;
        }
      );
    };
}
