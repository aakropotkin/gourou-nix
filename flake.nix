{
  description = "a basic package";

  inputs.utils.url = "github:numtide/flake-utils";

  inputs.pugixml-src = {
    url = "github:zeux/pugixml/latest";
    flake = false;
  };
  inputs.base64-src = {
    url = "git+https://gist.github.com/f0fd86b6c73063283afe550bc5d77594.git"; flake = false;
  };
  inputs.updfparser-src = {
    url = "git://soutade.fr/updfparser";
    flake = false;
  };
  inputs.gourou-src = {
    url = "git://soutade.fr/libgourou.git";
    type = "git";
    flake = false;
  };

  outputs = { self, nixpkgs, utils, pugixml-src, base64-src, updfparser-src, gourou-src }:
  let systemMap = utils.lib.eachSystemMap utils.lib.defaultSystems;
  in {
    packages = systemMap ( system:
      let pkgsFor = import nixpkgs { inherit system; };
      in rec {

        updfparser = pkgsFor.pkgsStatic.stdenv.mkDerivation {
          pname = "updfparser";
          version = "1.6.25-dev";
          src = updfparser-src;
          enableDebug = false;
          makeFlags = [
            "BUILD_STATIC=1"
            "BUILD_SHARED=0"
          ];
          configurePhase = ''
            runHook preConfigure
            : "''${enableDebug=0}"
            test "$enableDebug" != 0 && makeFlagsArray+=( DEBUG=1 )
            makeFlagsArray+=( CXXFLAGS="-I./include -static" )
            runHook postConfigure
          '';
          checkPhase = ''
            runHook preCheck
            make test && ./test
            runHook postCheck
          '';
          pkgConfigDef = ''
            prefix=@out@
            exec_prefix=''${prefix}
            libdir=''${prefix}/lib
            includedir=''${prefix}/include

            Name: updfparser
            Description: updfparser
            Version: 1.6.25-dev
            Libs: -L''${libdir} -lupdfparser
            Cflags: -I''${includedir}
          '';
          passAsFile = ["pkgConfigDef"];
          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib $out/lib/pkgconfig
            mv include $out/
            mv -- libupdfparser.a $out/lib/
            substitute "$pkgConfigDefPath"                 \
                       "$out/lib/pkgconfig/updfparser.pc"  \
              --subst-var out
            runHook postInstall
          '';
        };

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

        libgourou = pkgsFor.pkgsStatic.stdenv.mkDerivation rec {
          pname = "libgourou";
          version = "0.7.1";
          src = gourou-src;
          nativeBuildInputs = with pkgsFor.pkgsStatic; [pkg-config];
          buildInputs = ( with pkgsFor.pkgsStatic; [
            openssl.dev
            openssl.out
#            qt5.qtbase.dev
            libzipStatic.out
            curl.dev
            curl.out
          ] ) ++ [( updfparser.overrideAttrs ( _: { inherit enableDebug; } ) )];

          enableDebug = false;

          preConfigure = ''
            rm -rf lib scripts
            mkdir lib
            cp -pr --reflink=auto ${pugixml-src} lib/pugixml
            cp -pr --reflink=auto ${base64-src} lib/base64
            chmod -R u+w lib
          '';

          makeFlags = ["BUILD_SHARED=0" "BUILD_STATIC=1" "STATIC_UTILS=1"];

          CXXFLAGS = [
            "-Wall"
            "-I./include"
            "-fkeep-inline-functions"
            #"-fkeep-static-functions"
            "-fkeep-static-consts"
            #"-static-libgcc"
            "-static"
            "-Wl,-Bstatic"
          ] ++ ( if enableDebug then ["-ggdb" "-O0"] else ["-O2"] );

          configurePhase = ''
            runHook preConfigure
            : "''${enableDebug=0}"
            test "$enableDebug" != 0 && makeFlagsArray+=( DEBUG=1 )
            updfparser_CFLAGS="$( pkg-config --cflags updfparser; )"
            CXXFLAGS+=" $updfparser_CFLAGS"
            CXXFLAGS+=" -I$PWD/include"
            CXXFLAGS+=" -I$PWD/lib"
            CXXFLAGS+=" -I$PWD/lib/pugixml/src"
            CXXFLAGS+=" $( pkg-config --cflags openssl)"
            CXXFLAGS+=" $( pkg-config --cflags libcurl)"
            makeFlagsArray+=( CXXFLAGS="$CXXFLAGS" )
            updfparser_LIBS+="$( pkg-config --variable=libdir updfparser; )"
            makeFlagsArray+=( UPDFPARSERLIB="$updfparser_LIBS/libupdfparser.a" )
            LDFLAGS+=" $( pkg-config --static --libs libcurl )"
            LDFLAGS+=" $( pkg-config --static --libs openssl )"
            makeFlagsArray+=( LDFLAGS="$LDFLAGS" )
            runHook postConfigure
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib $out/bin
            mv -- libgourou.a $out/lib/
            mv -- utils/{acsmdownloader,adept_{activate,remove,loan_mgt}}  \
                  $out/bin/
            runHook postInstall
          '';

          dontWrapQtApps = true;
        };

        default = libgourou;
      }
    );
  };
}

