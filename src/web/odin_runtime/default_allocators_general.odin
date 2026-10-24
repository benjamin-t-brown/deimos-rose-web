#+build js wasm32, js wasm64p32
package runtime

// Replaces the stock file for the web compile. See emscripten_heap.odin.
default_allocator :: emscripten_heap_allocator
default_allocator_proc :: emscripten_heap_allocator_proc
