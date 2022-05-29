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
