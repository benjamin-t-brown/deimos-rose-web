#+build js wasm32, js wasm64p32
#+private
package os

import "base:runtime"
import "core:strings"

_info_from_path :: proc(name: string, allocator: runtime.Allocator) -> (fi: File_Info, err: Error) {
	temp_allocator := TEMP_ALLOCATOR_GUARD({})
	cstr := clone_to_cstring(name, temp_allocator) or_return
	if dr_exists(cstr) == 0 {
		return {}, .Not_Exist
	}
	fi.fullpath = strings.clone(name, allocator) or_return
	_, fi.name = split_path(fi.fullpath)
	fi.size = dr_file_size(cstr)
	fi.type = dr_is_dir(cstr) != 0 ? .Directory : .Regular
	return
}

_fstat :: proc(f: ^File, allocator: runtime.Allocator) -> (fi: File_Info, err: Error) {
	if f == nil {
		return {}, .Invalid_File
	}
	return _info_from_path(_name(f), allocator)
}

_stat :: proc(name: string, allocator: runtime.Allocator) -> (fi: File_Info, err: Error) {
	return _info_from_path(name, allocator)
}

_lstat :: proc(name: string, allocator: runtime.Allocator) -> (fi: File_Info, err: Error) {
	return _info_from_path(name, allocator)
}

_same_file :: proc(fi1, fi2: File_Info) -> bool {
	return fi1.fullpath == fi2.fullpath
}

_is_reserved_name :: proc(path: string) -> bool {
	_ = path
	return false
}
