package game

// One file the browser's Extras page downloads and uploads. Progress,
// preferences, high scores and each campaign's progress are the text
// files prefs.user_data_write already stores; this only bundles them.
//
// deimos-rose-save 1
// <count>
// <name>
// <byte length>
// <that many bytes, with no extra separator>
// repeated for each file. A name is one line of letters, digits, '.',
// '_' and '-'. Anything else, or a length that does not fit, is refused
// and nothing is written.

import "base:runtime"
import "core:fmt"
import "core:strconv"
import "core:strings"

SAVE_BUNDLE_MAGIC :: "deimos-rose-save 1\n"

Save_File :: struct {
	name: string,
	data: []byte,
}

save_name_ok :: proc(name: string) -> bool {
	if len(name) == 0 || len(name) > 64 {
		return false
	}
	if name == "." || name == ".." {
		return false
	}
	for c in name {
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '_', '-', '.':
		case:
			return false
		}
	}
	return true
}

@(private = "file")
split_line :: proc(s: string) -> (line, rest: string, ok: bool) {
	for i in 0 ..< len(s) {
		if s[i] == '\n' {
			return s[:i], s[i + 1:], true
		}
		if s[i] == '\r' {
			return "", "", false
		}
	}
	return "", "", false
}

save_bundle_pack :: proc(files: []Save_File, allocator := context.allocator) -> []byte {
	b := strings.builder_make(allocator)
	defer strings.builder_destroy(&b)
	strings.write_string(&b, SAVE_BUNDLE_MAGIC)
	fmt.sbprintf(&b, "%d\n", len(files))
	for f in files {
		fmt.sbprintf(&b, "%s\n%d\n", f.name, len(f.data))
		strings.write_string(&b, string(f.data))
	}
	out := make([]byte, len(b.buf), allocator)
	copy(out, b.buf[:])
	return out
}

@(private = "file")
save_bundle_free :: proc(files: [dynamic]Save_File, allocator: runtime.Allocator) {
	for f in files {
		delete(f.name, allocator)
		delete(f.data, allocator)
	}
	delete(files)
}

// ok is false when the bytes are not a bundle. Partial allocations from a
// failed parse are freed. The returned names and bytes belong to allocator.
save_bundle_unpack :: proc(bundle: []byte, allocator := context.allocator) -> (files: [dynamic]Save_File, ok: bool) {
	s := string(bundle)
	magic := SAVE_BUNDLE_MAGIC
	if !strings.has_prefix(s, magic) {
		return nil, false
	}
	rest := s[len(magic):]
	line: string
	cut: bool
	line, rest, cut = split_line(rest)
	if !cut {
		return nil, false
	}
	count, parsed := strconv.parse_int(line)
	if !parsed || count < 0 || count > 64 {
		return nil, false
	}
	files = make([dynamic]Save_File, 0, count, allocator)
	for _ in 0 ..< count {
		name: string
		name, rest, cut = split_line(rest)
		if !cut || !save_name_ok(name) {
			save_bundle_free(files, allocator)
			return nil, false
		}
		len_line: string
		len_line, rest, cut = split_line(rest)
		if !cut {
			save_bundle_free(files, allocator)
			return nil, false
		}
		n, parsed_n := strconv.parse_int(len_line)
		if !parsed_n || n < 0 || n > 262144 || n > len(rest) {
			save_bundle_free(files, allocator)
			return nil, false
		}
		data := make([]byte, n, allocator)
		copy(data, rest[:n])
		append(&files, Save_File{name = strings.clone(name, allocator), data = data})
		rest = rest[n:]
	}
	if len(rest) != 0 {
		save_bundle_free(files, allocator)
		return nil, false
	}
	return files, true
}
