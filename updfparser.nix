{ stdenv, src, enableDebug ? false, /* enableStatic ? false */ }:
stdenv.mkDerivation {
  pname = "updfparser";
  version = "1.6.25-dev";
  inherit src enableDebug;
  outputs = ["out" "dev"];
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
}
