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

        libupdfparser = support.mkCxxLibs {
          name = "libupdfparser";
          src = updfparser-src;
        };

        libgourou = support.mkCxxLibs {
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
          optArgOverride = support.mkLibOverride libupdfparser "opt";
          dbgArgOverride = support.mkLibOverride libupdfparser "dbg";
        };

        utils = support.mkCxxArchives {
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

        toolObjs =
          let
            # Yank flags from arbitrary object file in utils.
            flags = ( builtins.head ( utils.opt.static.files ) ).flags;
            compileMain = f:
              support.compileCxx flags "${gourou-src}/utils/${f}.cpp";
            binObjs = map ( b: { name = b; value = compileMain b; } ) [
              "acsmdownloader"
              "adept_activate"
              "adept_remove"
              "adept_loan_mgt"
            ];
          in map ( x: x.value ) binObjs;

        mkBin = cxxLinkFlags': obj:
          support.linkCxxExecutable {
            name = builtins.head ( builtins.split "\\." obj.name );
            files = [obj.outPath];
            cxxLinkFlags = ["-Wl,--as-needed"] ++ cxxLinkFlags';
          };

        binsDsoDeps =
          let cxxLinkFlags = [
                utils.opt.static.outPath
                libgourou.archives.opt.static.outPath
                libupdfparser.archives.opt.static.outPath
                "${pkgsFor.libzip}/lib/libzip.so"
                "${pkgsFor.zlib}/lib/libz.so"
                "${pkgsFor.openssl.out}/lib/libcrypto.so"
                "${pkgsFor.curl.out}/lib/libcurl.so"
              ];
          in map ( mkBin cxxLinkFlags ) toolObjs;

        libzipStatic = pkgsFor.libzip.overrideAttrs ( prev: {
          cmakeFlags = ( prev.cmakeFlags or [] ) ++ ["-DBUILD_SHARED_LIBS=OFF"];
        } );

        binsStaticDeps =
          let cxxLinkFlags = [
                "-Wl,-Bstatic"
                utils.opt.static.outPath
                libgourou.archives.opt.static.outPath
                libupdfparser.archives.opt.static.outPath
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
                #"${pkgsFor.pkgsStatic.stdenv.cc.libc_lib}/lib/libm.a"
                #"${pkgsFor.pkgsStatic.stdenv.cc.libc_lib}/lib/libc.a"
                "-static-libgcc"
                "-static-libstdc++"
                "-Wl,--end-group"
              ];
          in map ( mkBin cxxLinkFlags ) toolObjs;

      in rec {
        gourou = support.mkBinDir "gourou" binsDsoDeps;
        gourouStatic = support.mkBinDir "gourou-static" binsStaticDeps;
        inherit libzipStatic;
        default = gourouStatic;
      }
    );
  };
}
