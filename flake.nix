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
          support = import ./support.nix {
            inherit (pkgsFor) stdenv linkFarmFromDrvs;
          };
        in rec {
          base64 = import ./base64.nix {
            inherit system;
            inherit (pkgsFor) bash coreutils;
            src = base64-src;
          };

          updfparser =
            let full = import ./updfparser.nix {
                  inherit support;
                  src = updfparser-src;
                };
            in full.archives.all;

          libgourou = import ./libgourou.nix {
            inherit (pkgsFor) stdenv openssl libzip curl;
            inherit base64 updfparser;
            src = gourou-src;
            enableStatic = true;
            enableDebug  = false;
            disableWall  = true;
          };

          default = libgourou;
        }
      );
    };
}
