{ system, src, bash, coreutils }:
derivation {
  name = "base64";
  inherit system;
  builder = "${bash}/bin/bash";
  args = [
    "-c"
    ( "${coreutils}/bin/mkdir -p $out/include/base64; " +
      "${coreutils}/bin/cp -p --reflink=auto -- ${src}/Base64.h " +
      "$out/include/base64/" )
  ];
}
