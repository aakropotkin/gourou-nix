{ src, support }:
let
  archives = support.mkCxxArchives { name = "libupdfparser"; inherit src; };
  sharedLibs =
    let
      opt = support.mkCxxSharedLibrary {
        name = "libupdfparser.so";
        picArchive = archives.opt.pic;
      };
      dbg = support.mkCxxSharedLibrary {
        name = "libupdfparser-dbg.so";
        soname = "libupdfparser.so";
        picArchive = archives.dbg.pic;
      };
    in {
      inherit opt dbg;
      all = support.linkFarmFromDrvs "libupdfparser-lib-shared" [opt dbg];
    };
in {
  inherit archives sharedLibs;
  source = support.sourceDrv "updfparser-source" src;
  all = support.linkFarmFromDrvs "libupdfparser-lib" [
    archives.opt.static archives.opt.pic sharedLibs.opt
    archives.dbg.static archives.dbg.pic sharedLibs.dbg
  ];
}
