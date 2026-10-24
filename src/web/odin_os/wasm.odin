#+build js wasm32, js wasm64p32
package os

// The stock file is only `#panic("core:os is unsupported on js/wasm")`.
// build_web.sh copies this over it for the web compile. The js backends
// (file_js.odin and the rest) then compile, and the ones this build replaces
// talk to emscripten's filesystem through web/fs_em.c.
