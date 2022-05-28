{
  description = "a basic package";

  inputs.utils.url = "github:numtide/flake-utils";

  inputs.pugixml-src = {
    url = "github:zeux/pugixml/latest";
    flake = false;
  };
  inputs.base64-src = {
    url = "git+https://gist.github.com/f0fd86b6c73063283afe550bc5d77594.git";
    flake = false;
  };
  inputs.updfparser-src = {
    url = "git://soutade.fr/updfparser";
    flake = false;
  };

  outputs = { self, nixpkgs, utils, pugixml-src, base64-src, updfparser-src }:
  let systemMap = utils.lib.eachSystemMap utils.lib.defaultSystems;
  in {
    packages = systemMap ( system:
      let pkgsFor = import nixpkgs { inherit system; };
      in rec {

        updfparser = pkgsFor.stdenv.mkDerivation {
          pname = "updfparser";
          version = "1.6.25-dev";
          src = updfparser-src;
          outputs = ["out" "dev"];
          enableDebug = false;
          makeFlags = ["BUILD_STATIC=1"];
          configurePhase = ''
            runHook preConfigure

            : "''${enableDebug=0}"
            test "$enableDebug" != 0 && makeFlagsArray+=( DEBUG=1 )

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
            dev_prefix=@dev@
            libdir=''${prefix}/lib
            dev_libdir=''${dev_prefix}/lib
            includedir=''${dev_prefix}/include

            Name: updfparser
            Description: updfparser
            Version: 1.6.25-dev
            Libs: -L''${dev_libdir} -L''${libdir} -lupdfparser
            Cflags: -I''${includedir}
          '';
          passAsFile = ["pkgConfigDef"];
          installPhase = ''
            runHook preInstall

            mkdir -p $out/lib $dev/lib/pkgconfig $dev
            mv -- libupdfparser.so $out/lib/

            mv include $dev/
            mv -- libupdfparser.a $dev/lib/
            substitute $pkgConfigDefPath $dev/lib/pkgconfig/updfparser.pc  \
                       --subst-var out --subst-var dev

            runHook postInstall
          '';
        };

        libgourou = pkgsFor.stdenv.mkDerivation rec {
          pname = "libgourou";
          version = "0.7.1";
          src = self;
          nativeBuildInputs = with pkgsFor; [
            pkg-config
          ];
          buildInputs = ( with pkgsFor; [
            openssl.dev
            qt5.qtbase.dev
            ( libzip.dev.overrideAttrs ( prev: {
                stdenv = pkgsFor.makeStatic prev.stdenv;
              } ) )
            curl.dev
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
            makeFlagsArray+=( CXXFLAGS="$CXXFLAGS" )

            updfparser_LIBS+="$( pkg-config --variable=dev_libdir updfparser; )"
            makeFlagsArray+=( UPDFPARSERLIB="$updfparser_LIBS/libupdfparser.a" )

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

