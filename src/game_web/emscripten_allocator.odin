// Allocator that uses emscripten's malloc/free instead of WASM's memory.grow.
// Copied from karl-zylinski/odin-raylib-web.

package game_web

import "base:runtime"
import "core:c"

foreign import "env"

foreign env {
	@(link_name="malloc")
	emscripten_malloc :: proc "c" (size: c.size_t) -> rawptr ---
	@(link_name="free")
	emscripten_free :: proc "c" (ptr: rawptr) ---
}

emscripten_allocator :: proc() -> runtime.Allocator {
	return runtime.Allocator {
		procedure = emscripten_allocator_proc,
		data = nil,
	}
}

emscripten_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		ptr := emscripten_malloc(c.size_t(size))
		if ptr == nil {
			return nil, .Out_Of_Memory
		}
		return ([^]byte)(ptr)[:size], .None

	case .Free:
		emscripten_free(old_memory)
		return nil, .None

	case .Resize, .Resize_Non_Zeroed:
		// emscripten has realloc, but for simplicity: alloc + copy + free
		new_ptr := emscripten_malloc(c.size_t(size))
		if new_ptr == nil {
			return nil, .Out_Of_Memory
		}
		runtime.mem_copy(new_ptr, old_memory, min(old_size, size))
		emscripten_free(old_memory)
		return ([^]byte)(new_ptr)[:size], .None

	case .Free_All, .Query_Features, .Query_Info:
		return nil, .Mode_Not_Implemented
	}

	return nil, .Mode_Not_Implemented
}
