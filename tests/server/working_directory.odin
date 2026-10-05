package server_test

import "base:runtime"
import "core:os"

// The game reads data/ and its configs from its install's root, which is assets/ in this
// repository; the tests run from the repository's root, so they step into it first.
@(init)
enter_assets :: proc "contextless" () {
	context = runtime.default_context()
	if os.change_directory("assets") != nil do panic("run the tests from the repository's root, where assets/ is")
}
