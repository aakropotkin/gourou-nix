{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils/master";
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

  outputs = {
    self
  , nixpkgs
  , flake-utils
  , gourou-src
  , updfparser-src
  , base64-src
  , pugixml-src
  }:
  let
    supportedSystems = ["x86_64-linux"];
    systemsMap = flake-utils.lib.eachSystemMap supportedSystems;
  in {
    packages = systemsMap ( system:
      let
        pkgsFor = import nixpkgs { inherit system; };
        support = import ./support.nix {
          inherit (pkgsFor) stdenv linkFarmFromDrvs;
        };
        supportStatic = import ./support.nix {
          inherit (pkgsFor.pkgsStatic) stdenv linkFarmFromDrvs;
        };

        base64 = derivation {
          name = "base64";
          inherit system;
          builder = "${pkgsFor.bash}/bin/bash";
          PATH = "${pkgsFor.coreutils}/bin";
          args = ["-c" ''
            mkdir -p $out/include/base64;
            cp -p --reflink=auto  ${base64-src}/Base64.h "$out/include/base64/"
          ''];
        };

        libupdfparser = supp: supp.mkCxxLibs {
          name = "libupdfparser";
          src = updfparser-src;
        };

        libgourou = supp: supp.mkCxxLibs {
          name = "libgourou";
          src = gourou-src;
          files = [
            "${gourou-src}/src/libgourou.cpp"
            "${gourou-src}/src/user.cpp"
            "${gourou-src}/src/device.cpp"
            "${gourou-src}/src/fulfillment_item.cpp"
            "${gourou-src}/src/loan_token.cpp"
            "${gourou-src}/src/bytearray.cpp"
            "${pugixml-src}/src/pugixml.cpp"
          ];
          includes = [
            "${base64}/include"
            "${gourou-src}/include"
            "${pugixml-src}/src"
            "${updfparser-src}/include"
          ];
          optArgOverride = supp.mkLibOverride libupdfparser "opt";
          dbgArgOverride = supp.mkLibOverride libupdfparser "dbg";
        };

        utils = supp: supp.mkCxxArchives {
          name = "util";
          includes = [
            "${gourou-src}/include"
            "${pugixml-src}/src"
            "${pkgsFor.openssl.dev}/include"
            "${pkgsFor.curl.dev}/include"
            "${pkgsFor.zlib.dev}/include"
            "${pkgsFor.libzip.dev}/include"
          ];
          files = [
            "${gourou-src}/utils/drmprocessorclientimpl.cpp"
            "${gourou-src}/utils/utils_common.cpp"
          ];
        };

        toolObjs = supp:
          let
            # Yank flags from arbitrary object file in utils.
            flags = ( builtins.head ( ( utils supp ).opt.static.files ) ).flags;
            compileMain = f:
              supp.compileCxx flags "${gourou-src}/utils/${f}.cpp";
            binObjs = map ( b: { name = b; value = compileMain b; } ) [
              "acsmdownloader"
              "adept_activate"
              "adept_remove"
              "adept_loan_mgt"
            ];
          in map ( x: x.value ) binObjs;

        mkBin = supp: cxxLinkFlags': obj:
          supp.linkCxxExecutable {
            name = builtins.head ( builtins.split "\\." obj.name );
            files = [obj.outPath];
            cxxLinkFlags = ["-Wl,--as-needed"] ++ cxxLinkFlags';
          };

        binsDsoDeps =
          let cxxLinkFlags = [
                ( utils support ).opt.static.outPath
                ( libgourou support ).archives.opt.static.outPath
                ( libupdfparser support ).archives.opt.static.outPath
                "${pkgsFor.libzip}/lib/libzip.so"
                "${pkgsFor.zlib}/lib/libz.so"
                "${pkgsFor.openssl.out}/lib/libcrypto.so"
                "${pkgsFor.curl.out}/lib/libcurl.so"
              ];
          in map ( mkBin support cxxLinkFlags ) ( toolObjs support );

        libzipStatic = pkgsFor.pkgsStatic.libzip.overrideAttrs ( prev: {
          cmakeFlags = ( prev.cmakeFlags or [] ) ++ [
            "-DBUILD_SHARED_LIBS=OFF"
            "-DBUILD_EXAMPLES=OFF"
            "-DBUILD_DOC=OFF"
            "-DBUILD_TOOLS=OFF"
            "-DBUILD_REGRESS=OFF"
          ];
          outputs = ["out"];
        } );

        binsStaticDeps =
          let cxxLinkFlags = [
                "-static"
                ( utils supportStatic ).opt.static.outPath
                ( libgourou supportStatic ).archives.opt.static.outPath
                ( libupdfparser supportStatic ).archives.opt.static.outPath
                "-Wl,--start-group"
                "${libzipStatic}/lib/libzip.a"
                "${pkgsFor.pkgsStatic.libnghttp2}/lib/libnghttp2.a"
                "${pkgsFor.pkgsStatic.libidn2.out}/lib/libidn2.a"
                "${pkgsFor.pkgsStatic.libunistring}/lib/libunistring.a"
                "${pkgsFor.pkgsStatic.libssh2}/lib/libssh2.a"
                "${pkgsFor.pkgsStatic.zstd.out}/lib/libzstd.a"
                "${pkgsFor.pkgsStatic.zlib}/lib/libz.a"
                "${pkgsFor.pkgsStatic.openssl.out}/lib/libcrypto.a"
                "${pkgsFor.pkgsStatic.curl.out}/lib/libcurl.a"
                "${pkgsFor.pkgsStatic.openssl.out}/lib/libssl.a"
                "-static-libgcc"
                "-static-libstdc++"
                "-Wl,--end-group"
              ];
          in map ( mkBin supportStatic cxxLinkFlags )
                 ( toolObjs supportStatic );

      in rec {
        gourou = support.mkBinDir "gourou" binsDsoDeps;
        gourouStatic = supportStatic.mkBinDir "gourou-static" binsStaticDeps;
        default = gourouStatic;
      }
    );
  };
}
