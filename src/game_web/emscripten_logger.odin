// Prints through emscripten's puts, which shows up in the browser console.
// Adapted from karl-zylinski/odin-raylib-web.

package game_web

import "core:c"
import "core:fmt"
import "core:log"
import "core:strings"

@(default_calling_convention = "c")
foreign {
	puts :: proc(buffer: cstring) -> c.int ---
}

create_emscripten_logger :: proc(lowest := log.Level.Debug, opt := log.Options{.Level}) -> log.Logger {
	return log.Logger{data = nil, procedure = logger_proc, lowest_level = lowest, options = opt}
}

@(private = "file")
logger_proc :: proc(
	logger_data: rawptr,
	level: log.Level,
	text: string,
	options: log.Options,
	location := #caller_location,
) {
	_, _, _ = logger_data, options, location
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "[%v] %s", level, text)
	if bc, bc_err := strings.to_cstring(&b); bc_err == nil {
		_ = puts(bc)
	}
}
