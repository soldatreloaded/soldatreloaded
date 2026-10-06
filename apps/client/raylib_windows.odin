#+build windows
package main

// raylib first on the link line. ENet, which the client now plays online through
// (core/network), links Winmm.lib, which has a PlaySound of its own: named before raylib,
// it is the PlaySound the link takes, and raylib's, coming after, is one too many.
// Named here, in the program's own package, whose libraries the link takes first,
// raylib's is the one.
@(require)
foreign import raylib_first "vendor:raylib/windows/raylib.lib"
