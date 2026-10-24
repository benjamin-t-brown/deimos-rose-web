// Logger that prints through emscripten's console.log.
// Copied from karl-zylinski/odin-raylib-web.

package game_web

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"

foreign import "env"

foreign env {
	@(link_name="emscripten_console_log")
	emscripten_console_log :: proc "c" (str: cstring) ---
}

create_emscripten_logger :: proc(
	lowest := log.Level.Debug,
	opt: log.Options = log.DEFAULT_CONSOLE_LOGGER_OPTS,
	ident := "",
	allocator := context.allocator,
) -> log.Logger {
	return log.Logger {
		procedure = emscripten_logger_proc,
		lowest_level = lowest,
		options = opt,
	}
}

emscripten_logger_proc :: proc(
	logger_data: rawptr,
	level: log.Level,
	text: string,
	options: log.Options,
	location := #caller_location,
) {
	backing: [1024]byte
	buf: []byte = backing[:]
	str: string

	if .Level in options {
		prefix: string
		switch level {
		case .Debug:   prefix = "[DEBUG]   "
		case .Info:    prefix = "[INFO]    "
		case .Warning: prefix = "[WARNING] "
		case .Error:   prefix = "[ERROR]   "
		case .Fatal:   prefix = "[FATAL]   "
		}
		str = fmt.bprintf(buf, "%s%s", prefix, text)
	} else {
		str = fmt.bprintf(buf, "%s", text)
	}

	// Ensure null termination
	if len(str) < len(buf) {
		buf[len(str)] = 0
	} else {
		buf[len(buf)-1] = 0
	}

	emscripten_console_log(cstring(raw_data(buf)))
}
