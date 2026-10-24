#+build js wasm32, js wasm64p32
#+private
package os

import "base:runtime"

// The stock proc is the wasm memory.grow allocator. File and temp arenas
// go through here, so they have to use emscripten's malloc like the rest
// of the web build (web/odin_runtime/emscripten_heap.odin).
_heap_allocator_proc :: runtime.emscripten_heap_allocator_proc
