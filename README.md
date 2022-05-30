# gourou-nix
Going off the deep end with Nix and C++. "Raw Derivations"

## What?
This bundle of Nix expressions started as "build trivially simple C++ library with Nix as a shared and static library".

When I found that the Makefiles needed to be refactored in minor ways ( classic "half-baked" Makefile situation, not a Nix issue ) I thought - "You know, if Nix is so fucking great why doesn't it just let me do something like `mkCxxProject`?".
The Makefiles themselves step into a classic pitfall of trying to perform Package Management and Configuration recursively with a build dispatcher ( y'all you need to stop doing this; if you use a network connection in `make` you've already fucked up - I say this dogmatically and unironically ).

In the field we commonly run into useful projects, where the build scripts themselves are total dogshit - as Package Management developers that leaves us with two options:
1. Grokk the existing build system, shake your head in a disappointed manner, and rewrite it.
2. Grokk the existing build system, shake your head in a disappointed manner, accept that the author was really to write cool software - not a robust build, and write a robust build utility that will allow authors to avoid thinking about build systems.

Naturally, this led to complicate things by building the universe, largely the contents of `support.nix`.

## Approach
Aside from Makefile avoidance, parts of `support.nix` provide direct control of linkage to avoid quirks in `nixpkgs.stdenv`, `nixpkgs.pkgsStatic.stdenv`, and the `setup.sh` conditionals that try control static linkage.
When the `setup.sh` and `stdenv` routines are consistently supported forall dependencies, this control isn't really necessary; however, as is often the case, when any of our dependencies don't work consistently with `pkgsStatic.stdenv` and `stdenv` - being able to directly write link lines is a life saver.

In cases where existing `nixpkgs` were already supported by `pkgsStatic` I use them, but you may also see that in `flake.nix` I patch/override a few dependencies to get those builds to succeed.

## Room for Improvement
- One of the last changes I made to `support.nix` was allowing each function to accept `stdenv` as an argument, I found this was necessary to produce a completely static executable; these interface changes should be integrated more cleanly into `mkCxxArchives` and `mkCxxLibs` - specifically in distinguishing between static/pic forms of a library.
- `cxxLinkSharedLibrary` has too many arguments, and `mkCxxLibs` has wonky interfacing with them. If I were to rewrite them I'd honestly just expose a derivation generator like `cxx = name: flags: derivation { inherit name; builder = "${cc}/bin/c++"; args = ["-o" ( builtins.placeholder "out" )] ++ flags]; ... }` for cases where the level of control I was after was really warranted.
- The derivation generators which currently reference `g++` directly should instead use `c++`, and the routine used to lookup the tool name can use a simple conditional like `stdenv.hostPlatform.isMusl` to use `${cc}/bin/${stdenv.hostPlatform.config}-c++` rather than reading the filesystem.
- Library "sets" ought to automatically provide the proper archive/lib based on context, a simple accessor could provide this.
- Static Archives should track dependencies using a strategy similar to `pkg-config`. In fact, it would be pretty simple to parse `.pc` files to create library sets from them.
- Individual object file derivations open up the opportunity for adding things like symbol tables, `cpp` analysis results ( to track used headers in a fine grained manner ), and additional metadata for use in optimizing build pathways. In theory it's possible to effectively reduce inputs to their strictess minimum using `cpp`, `cc`, `ld`, and `nm` output. This seems like a natural progression of Nix's roots in `patchelf` and `RPATH` scraping/patching.
