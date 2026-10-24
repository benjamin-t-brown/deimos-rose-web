#+build js wasm32, js wasm64p32
package runtime

// malloc-backed heap for the web build. The stock default grows wasm memory
// itself, and emscripten's malloc does too; the two disagree about who owns
// the new pages. build_web.sh copies this in beside the runtime and points
// the default allocator at it.
//
// The padding matches base/runtime/heap_allocator.odin. A resize only calls
// realloc when the alignment is no tighter than a pointer; anything stricter
// allocates a new block and copies, because realloc does not keep the padding.

import "base:intrinsics"

@(default_calling_convention = "c")
foreign {
	@(link_name = "calloc") em_calloc :: proc(num, size: uint) -> rawptr ---
	@(link_name = "free") em_free :: proc(ptr: rawptr) ---
	@(link_name = "malloc") em_malloc :: proc(size: uint) -> rawptr ---
	@(link_name = "realloc") em_realloc :: proc(ptr: rawptr, size: uint) -> rawptr ---
}

emscripten_heap_allocator :: proc "contextless" () -> Allocator {
	return Allocator{emscripten_heap_allocator_proc, nil}
}

emscripten_heap_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (
	data: []byte,
	err: Allocator_Error,
) {
	_, _ = allocator_data, location

	aligned_alloc :: proc(size, alignment: int, old_ptr: rawptr, old_size: int, zero_memory: bool) -> ([]byte, Allocator_Error) {
		a := max(alignment, align_of(rawptr))
		space := a - 1 + size_of(rawptr) + size
		// realloc does not preserve a pad wider than a pointer.
		force_copy := old_ptr != nil && alignment > align_of(rawptr)

		allocated: rawptr
		if old_ptr != nil && !force_copy {
			header := rawptr(uintptr(old_ptr) - size_of(rawptr))
			original := (cast(^rawptr)header)^
			allocated = em_realloc(original, uint(space))
		} else if zero_memory {
			allocated = em_calloc(1, uint(space))
		} else {
			allocated = em_malloc(uint(space))
		}
		if allocated == nil {
			return nil, .Out_Of_Memory
		}

		aligned := uintptr(allocated) + size_of(rawptr)
		aligned = (aligned - 1 + uintptr(a)) & ~uintptr(a - 1)
		user := rawptr(aligned)
		(cast(^rawptr)rawptr(aligned - size_of(rawptr)))^ = allocated

		if force_copy {
			n := min(old_size, size)
			if n > 0 {
				intrinsics.mem_copy_non_overlapping(user, old_ptr, n)
			}
			aligned_free(old_ptr)
		}
		return byte_slice(user, size), nil
	}

	aligned_free :: proc(p: rawptr) {
		if p != nil {
			header := rawptr(uintptr(p) - size_of(rawptr))
			em_free((cast(^rawptr)header)^)
		}
	}

	aligned_resize :: proc(p: rawptr, old_size, new_size, new_alignment: int, zero_memory: bool) -> (new_memory: []byte, err: Allocator_Error) {
		if p == nil {
			return aligned_alloc(new_size, new_alignment, nil, old_size, zero_memory)
		}
		new_memory = aligned_alloc(new_size, new_alignment, p, old_size, zero_memory) or_return
		if zero_memory && new_size > old_size {
			intrinsics.mem_zero(raw_data(new_memory[old_size:]), new_size - old_size)
		}
		return
	}

	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		return aligned_alloc(size, alignment, nil, 0, mode == .Alloc)
	case .Free:
		aligned_free(old_memory)
		return nil, nil
	case .Free_All, .Query_Info:
		return nil, .Mode_Not_Implemented
	case .Resize, .Resize_Non_Zeroed:
		return aligned_resize(old_memory, old_size, size, alignment, mode == .Resize)
	case .Query_Features:
		set := cast(^Allocator_Mode_Set)old_memory
		if set != nil {
			set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Resize, .Resize_Non_Zeroed, .Query_Features}
		}
		return nil, nil
	}
	return nil, .Mode_Not_Implemented
}
