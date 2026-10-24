// Web entry point: exports procedures called from JavaScript in index.html.
// Adapted from karl-zylinski/odin-raylib-web.

package game_web

import "base:runtime"
import "core:c"
import "core:mem"
import "dr:game"
import _ "dr:all_plugins_no_netplay"

@(private="file")
web_context: runtime.Context

@export
main_start :: proc "c" () {
	context = runtime.default_context()

	// The WASM allocator doesn't work properly with emscripten. Use
	// emscripten's malloc instead.
	context.allocator = emscripten_allocator()
	runtime.init_global_temporary_allocator(1*mem.Megabyte)

	context.logger = create_emscripten_logger()

	web_context = context

	game.game_init_web()
}

@export
main_update :: proc "c" () -> bool {
	context = web_context
	ok := game.game_update_web()
	return ok
}

@export
main_end :: proc "c" () {
	context = web_context
	game.game_shutdown_web()
}

@export
web_window_size_changed :: proc "c" (w: c.int, h: c.int) {
	context = web_context
	game.game_window_size_changed(int(w), int(h))
}
