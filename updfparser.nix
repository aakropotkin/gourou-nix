{ src, support }: {
  archives = support.mkCxxArchives { name = "libupdfparser"; inherit src; };
  source = support.sourceDrv "updfparser-source" src;
}
