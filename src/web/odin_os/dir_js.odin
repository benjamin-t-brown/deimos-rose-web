#+build js wasm32, js wasm64p32
#+private
package os

import "core:strings"

Read_Directory_Iterator_Impl :: struct {
	names:   []byte,
	off:     int,
	prev_fi: File_Info,
}

_read_directory_iterator_init :: proc(it: ^Read_Directory_Iterator, f: ^File) {
	path := _name(f)
	temp_allocator := TEMP_ALLOCATOR_GUARD({})
	cstr, cerr := clone_to_cstring(path, temp_allocator)
	if cerr != nil {
		read_directory_iterator_set_error(it, path, .Invalid_Dir)
		return
	}

	cap := 1 << 16
	for cap <= 1 << 22 {
		buf, aerr := make([]byte, cap, file_allocator())
		if aerr != nil {
			read_directory_iterator_set_error(it, path, .Invalid_Dir)
			return
		}
		n := dr_list_dir(cstr, raw_data(buf), i32(len(buf)))
		if n == -2 {
			delete(buf, file_allocator())
			cap *= 2
			continue
		}
		if n < 0 {
			delete(buf, file_allocator())
			read_directory_iterator_set_error(it, path, .Invalid_Dir)
			return
		}
		it.impl.names = buf[:n]
		it.impl.off = 0
		return
	}
	read_directory_iterator_set_error(it, path, .Invalid_Dir)
}

@(require_results)
_read_directory_iterator :: proc(it: ^Read_Directory_Iterator) -> (fi: File_Info, index: int, ok: bool) {
	names := it.impl.names
	off := it.impl.off
	if off >= len(names) {
		return
	}
	start := off
	for off < len(names) && names[off] != 0 {
		off += 1
	}
	name := string(names[start:off])
	if off < len(names) {
		off += 1
	}
	it.impl.off = off

	parent := _name(it.f)
	full, aerr := strings.concatenate({parent, "/", name}, file_allocator())
	if aerr != nil {
		read_directory_iterator_set_error(it, parent, .Invalid_Dir)
		return
	}
	info, serr := _stat(full, file_allocator())
	if serr != nil {
		read_directory_iterator_set_error(it, full, serr)
		delete(full, file_allocator())
		return
	}
	file_info_delete(it.impl.prev_fi, file_allocator())
	it.impl.prev_fi = info
	index = it.index
	it.index += 1
	return info, index, true
}

_read_directory_iterator_destroy :: proc(it: ^Read_Directory_Iterator) {
	delete(it.impl.names, file_allocator())
	it.impl.names = nil
	file_info_delete(it.impl.prev_fi, file_allocator())
	it.impl.prev_fi = {}
}
