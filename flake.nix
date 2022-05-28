{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  inputs.updfparser = {
    url = "git://soutade.fr/updfparser";
    flake = false;
  };

  inputs.base64 = {
    url = "git+https://gist.github.com/f0fd86b6c73063283afe550bc5d77594.git";
    flake = false;
  };

  outputs = flakes:
    let
      nixpkgs = flakes.nixpkgs.legacyPackages.x86_64-linux;
      self = flakes.self;
      updfparser = flakes.updfparser;
      base64 = flakes.base64;
    in {
      defaultPackage.x86_64-linux = nixpkgs.stdenv.mkDerivation {
        pname = "the-scroll";
        version = "0.5.3";
        stdenv = nixpkgs.stdenv.hostPlatform.override { isStatic = true; };
        src = self;
        dontDisableStatic = true;
        nativeBuildInputs = [
          nixpkgs.pkg-config
          nixpkgs.meson
          nixpkgs.ninja
        ];
        buildInputs = [
          nixpkgs.openssl
          nixpkgs.qt5.qtbase
          nixpkgs.libzip
          nixpkgs.pugixml
        ];
        preConfigure = ''
          mkdir -p lib
          cp -pr --reflink=auto -- ${updfparser} lib/updfparser
          cp -pr --reflink=auto -- ${base64} lib/base64
          chmod -R u+w lib
        '';
        configurePhase = ''
          runHook preConfigure

          pushd lib/updfparser
          make BUILD_STATIC=1 BUILD_SHARED=0
          popd

          mesonFlags="''${mesonFlags:+$mesonFlags }-Ddefault_library=static"

          meson $mesonFlags build

          runHook postConfigure
       '';
       buildPhase = ''
         runHook preBuild

         cd build
         ninja

         runHook postBuild
       '';
       installPhase = ''
         runHook preInstall

         mkdir -p $out/lib $out/bin
         cp libthe-scroll.a $out/lib/the-scroll.a
         cp gourou-activate $out/bin
         cp gourou-download $out/bin
         cp gourou-dedrm $out/bin

         runHook postInstall
       '';
       dontWrapQtApps = true;
    };
  };
}
