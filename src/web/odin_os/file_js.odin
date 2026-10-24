#+build js wasm32, js wasm64p32
#+private
package os

import "base:runtime"
import "core:io"
import "core:strings"
import "core:time"

File_Impl :: struct {
	file:      File,
	handle:    rawptr,
	name:      string,
	allocator: runtime.Allocator,
	is_dir:    bool,
}

@(default_calling_convention = "c")
foreign {
	dr_fopen     :: proc(filename, mode: cstring) -> rawptr ---
	dr_fclose    :: proc(f: rawptr) -> i32 ---
	dr_fread     :: proc(ptr: rawptr, n: i64, f: rawptr) -> i64 ---
	dr_fwrite    :: proc(ptr: rawptr, n: i64, f: rawptr) -> i64 ---
	dr_fseek     :: proc(f: rawptr, off: i64, whence: i32) -> i32 ---
	dr_ftell     :: proc(f: rawptr) -> i64 ---
	dr_fflush    :: proc(f: rawptr) -> i32 ---
	dr_exists    :: proc(path: cstring) -> i32 ---
	dr_is_dir    :: proc(path: cstring) -> i32 ---
	dr_file_size :: proc(path: cstring) -> i64 ---
	dr_list_dir  :: proc(path: cstring, buf: rawptr, buflen: i32) -> i32 ---
}

_open :: proc(name: string, flags: File_Flags, perm: Permissions) -> (f: ^File, err: Error) {
	_ = perm
	temp_allocator := TEMP_ALLOCATOR_GUARD({})
	name_cstr := clone_to_cstring(name, temp_allocator) or_return

	impl := new(File_Impl, file_allocator()) or_return
	impl.allocator = file_allocator()
	impl.name = strings.clone(name, impl.allocator) or_return
	impl.file.impl = impl
	impl.file.stream = {
		data = impl,
		procedure = _file_stream_proc,
	}

	if dr_is_dir(name_cstr) != 0 {
		impl.is_dir = true
		return &impl.file, nil
	}

	mode: cstring = "rb"
	switch flags & (O_RDONLY | O_WRONLY | O_RDWR) {
	case O_RDONLY:
		mode = "rb"
	case O_WRONLY:
		mode = .Append in flags ? "ab" : "wb"
	case O_RDWR:
		mode = "r+b"
	}
	impl.handle = dr_fopen(name_cstr, mode)
	if impl.handle == nil {
		delete(impl.name, impl.allocator)
		free(impl, impl.allocator)
		return nil, .Not_Exist
	}
	return &impl.file, nil
}

_new_file :: proc(handle: uintptr, name: string, allocator: runtime.Allocator) -> (f: ^File, err: Error) {
	_ = handle
	_ = name
	_ = allocator
	return nil, .Unsupported
}

_clone :: proc(f: ^File) -> (clone: ^File, err: Error) {
	_ = f
	return nil, .Unsupported
}

_close :: proc(f: ^File_Impl) -> (err: Error) {
	if f == nil {
		return nil
	}
	if f.handle != nil {
		_ = dr_fclose(f.handle)
		f.handle = nil
	}
	return nil
}

_fd :: proc(f: ^File) -> uintptr {
	_ = f
	return 0
}

_is_tty :: proc "contextless" (f: ^File) -> bool {
	_ = f
	return false
}

_name :: proc(f: ^File) -> string {
	if f == nil || f.impl == nil {
		return ""
	}
	return (^File_Impl)(f.impl).name
}

_sync :: proc(f: ^File) -> Error {
	_ = f
	return nil
}

_truncate :: proc(f: ^File, size: i64) -> Error {
	_ = f
	_ = size
	return .Unsupported
}

_remove :: proc(name: string) -> Error {
	_ = name
	return .Unsupported
}

_rename :: proc(old_path, new_path: string) -> Error {
	_ = old_path
	_ = new_path
	return .Unsupported
}

_link :: proc(old_name, new_name: string) -> Error {
	_ = old_name
	_ = new_name
	return .Unsupported
}

_symlink :: proc(old_name, new_name: string) -> Error {
	_ = old_name
	_ = new_name
	return .Unsupported
}

_read_link :: proc(name: string, allocator: runtime.Allocator) -> (s: string, err: Error) {
	_ = name
	_ = allocator
	return "", .Unsupported
}

_chdir :: proc(name: string) -> Error {
	_ = name
	return .Unsupported
}

_fchdir :: proc(f: ^File) -> Error {
	_ = f
	return .Unsupported
}

_fchmod :: proc(f: ^File, mode: Permissions) -> Error {
	_ = f
	_ = mode
	return .Unsupported
}

_chmod :: proc(name: string, mode: Permissions) -> Error {
	_ = name
	_ = mode
	return .Unsupported
}

_fchown :: proc(f: ^File, uid, gid: int) -> Error {
	_ = f
	_ = uid
	_ = gid
	return .Unsupported
}

_chown :: proc(name: string, uid, gid: int) -> Error {
	_ = name
	_ = uid
	_ = gid
	return .Unsupported
}

_lchown :: proc(name: string, uid, gid: int) -> Error {
	_ = name
	_ = uid
	_ = gid
	return .Unsupported
}

_chtimes :: proc(name: string, atime, mtime: time.Time) -> Error {
	_ = name
	_ = atime
	_ = mtime
	return .Unsupported
}

_fchtimes :: proc(f: ^File, atime, mtime: time.Time) -> Error {
	_ = f
	_ = atime
	_ = mtime
	return .Unsupported
}

_exists :: proc(path: string) -> bool {
	temp_allocator := TEMP_ALLOCATOR_GUARD({})
	cstr := clone_to_cstring(path, temp_allocator) or_else ""
	if cstr == "" {
		return false
	}
	return dr_exists(cstr) != 0
}

@(private = "file")
_file_stream_proc :: proc(stream_data: rawptr, mode: File_Stream_Mode, p: []byte, offset: i64, whence: io.Seek_From, allocator: runtime.Allocator) -> (n: i64, err: Error) {
	f := (^File_Impl)(stream_data)
	switch mode {
	case .Read:
		if f == nil || f.handle == nil {
			return 0, .Invalid_File
		}
		n = dr_fread(raw_data(p), i64(len(p)), f.handle)
		if n == 0 {
			err = .EOF
		}
		return
	case .Read_At:
		if f == nil || f.handle == nil {
			return 0, .Invalid_File
		}
		if dr_fseek(f.handle, offset, 0) != 0 {
			return 0, .Invalid_Offset
		}
		n = dr_fread(raw_data(p), i64(len(p)), f.handle)
		if n == 0 {
			err = .EOF
		}
		return
	case .Write:
		if f == nil || f.handle == nil {
			return 0, .Invalid_File
		}
		n = dr_fwrite(raw_data(p), i64(len(p)), f.handle)
		if n != i64(len(p)) {
			err = .Short_Write
		}
		return
	case .Write_At:
		if f == nil || f.handle == nil {
			return 0, .Invalid_File
		}
		if dr_fseek(f.handle, offset, 0) != 0 {
			return 0, .Invalid_Offset
		}
		n = dr_fwrite(raw_data(p), i64(len(p)), f.handle)
		if n != i64(len(p)) {
			err = .Short_Write
		}
		return
	case .Seek:
		if f == nil || f.handle == nil {
			return 0, .Invalid_File
		}
		if dr_fseek(f.handle, offset, i32(whence)) != 0 {
			return 0, .Invalid_Whence
		}
		return dr_ftell(f.handle), nil
	case .Size:
		if f == nil || f.handle == nil {
			if f != nil && f.is_dir {
				return 0, nil
			}
			return 0, .Invalid_File
		}
		cur := dr_ftell(f.handle)
		if dr_fseek(f.handle, 0, 2) != 0 {
			return 0, .Unsupported
		}
		n = dr_ftell(f.handle)
		_ = dr_fseek(f.handle, cur, 0)
		return
	case .Flush:
		if f != nil && f.handle != nil {
			_ = dr_fflush(f.handle)
		}
		return 0, nil
	case .Close, .Destroy:
		if f != nil {
			err = _close(f)
			if mode == .Destroy {
				delete(f.name, f.allocator)
				free(f, f.allocator)
			}
		}
		return
	case .Query:
		return io.query_utility({.Read, .Read_At, .Write, .Write_At, .Seek, .Size, .Flush, .Close, .Destroy, .Query})
	case .Fstat:
		err = file_stream_fstat_utility(f, p, allocator)
		return
	}
	return 0, .Unsupported
}
