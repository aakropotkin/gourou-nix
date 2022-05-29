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
          libupdfparser = support.mkCxxLibs {
            name = "libupdfparser";
            src = updfparser-src;
          };
          updfOv = support.mkLibOverride libupdfparser;
        in rec {
          base64 = import ./base64.nix {
            inherit system;
            inherit (pkgsFor) bash coreutils;
            src = base64-src;
          };

          updfparser = libupdfparser.all;

          libgourou = ( support.mkCxxLibs {
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
            optArgOverride = updfOv "opt";
            dbgArgOverride = updfOv "dbg";
          } ).all;

          default = libgourou;
        }
      );
    };
}
